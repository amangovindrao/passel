"""Play the shop's part in an order, so the rest of the chain can be tested.

The shop app has onboarding, a catalogue and a subscription screen, but no order
management — that is Phase 9 and it does not exist yet. Which means that on a
phone, an order placed by the customer app stops dead: nobody can accept it, so
it never reaches the rider, and the two features that do exist on either side of
that gap cannot be seen working together.

This stands in for the missing screens. It drives the real HTTP endpoints as the
real shop owner, so the state machine, its guards and partner matching all run
exactly as they would in production — only the taps are missing.

    # Show what is waiting, change nothing
    python scripts/drive_order.py --list

    # Accept, pack and hand off every placed order, one at a time
    python scripts/drive_order.py --anon-key <key>

    # Watch for new orders and drive each as it arrives
    python scripts/drive_order.py --anon-key <key> --watch

Dev only. `--list` is read-only; everything else moves real rows.
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys

import httpx
from sqlalchemy import select

from app.core.database import SessionFactory
from app.domain.enums import OrderStatus
from app.models.entities import DeliveryAssignment, Order, Shop

DEFAULT_SUPABASE = "http://127.0.0.1:54321"
DEFAULT_API = "http://127.0.0.1:8000"

# The shop owner seeded by seed_demo.py --claim, and the fixed OTP from
# supabase/config.toml.
OWNER_PHONE = "+919900000002"
OTP = "123456"

# The packing photo is a state-machine guard, not something anyone looks at
# here — PREPARING will not advance to READY_FOR_PICKUP without one.
PLACEHOLDER_PHOTO = "https://placehold.co/600x400?text=packed"


async def sign_in(supabase: httpx.AsyncClient, anon_key: str) -> str:
    """Phone OTP against the local stack, the same two calls the app makes."""
    headers = {"apikey": anon_key, "Content-Type": "application/json"}

    sent = await supabase.post(
        "/auth/v1/otp", headers=headers, json={"phone": OWNER_PHONE}
    )
    if sent.status_code >= 400:
        raise RuntimeError(f"otp request failed: {sent.status_code} {sent.text}")

    verified = await supabase.post(
        "/auth/v1/verify",
        headers=headers,
        json={"type": "sms", "phone": OWNER_PHONE, "token": OTP},
    )
    if verified.status_code >= 400:
        raise RuntimeError(
            f"otp verify failed: {verified.status_code} {verified.text}"
        )
    token = verified.json().get("access_token")
    if not token:
        raise RuntimeError("no access_token in the verify response")
    return token


async def waiting_orders(statuses: tuple[str, ...]) -> list[dict]:
    """Orders sitting in any of `statuses`, oldest first.

    Reads the database rather than the API because `--list` is meant to work
    with no credentials at all. Everything that *changes* an order goes through
    HTTP as the real owner; this is only for looking.
    """
    async with SessionFactory() as db:
        rows = (
            await db.execute(
                select(Order, Shop.name)
                .join(Shop, Shop.id == Order.shop_id)
                .where(Order.status.in_(statuses))
                .order_by(Order.created_at.asc())
            )
        ).all()
        return [
            {
                "id": str(order.id),
                "shop": shop_name,
                "status": order.status,
                "payment_mode": order.payment_mode,
                "payment_status": order.payment_status,
                "total_paise": order.item_total_paise + order.delivery_fee_paise,
                "created_at": order.created_at,
            }
            for order, shop_name in rows
        ]


async def shop_queue(
    api: httpx.AsyncClient, auth: dict, shop_id: str
) -> list[dict]:
    """The queue as the shop app sees it, over the real endpoint.

    Worth exercising here as well as in the app: this is the endpoint Phase 9
    added, and a mismatch between what the script drives and what a shopkeeper
    is looking at would be a confusing way to find out.
    """
    resp = await api.get(f"/api/v1/shops/{shop_id}/orders", headers=auth)
    if resp.status_code != 200:
        print(f"    ERR shop order queue -> {resp.status_code} {resp.text[:120]}")
        return []
    return resp.json()


async def assignment_for(order_id: str) -> dict | None:
    async with SessionFactory() as db:
        assignment = await db.scalar(
            select(DeliveryAssignment)
            .where(DeliveryAssignment.order_id == order_id)
            .order_by(DeliveryAssignment.assigned_at.desc())
        )
        if assignment is None:
            return None
        return {
            "id": str(assignment.id),
            "partner_id": str(assignment.partner_id),
            "status": assignment.status,
            "offer_type": assignment.offer_type,
            "pickup_code": assignment.pickup_code,
        }


async def _step(
    api: httpx.AsyncClient, auth: dict, label: str, path: str, **kwargs
) -> bool:
    resp = await api.post(path, headers=auth, **kwargs)
    ok = resp.status_code == 200
    marker = "ok " if ok else "ERR"
    print(f"    {marker} {label:16s} {resp.status_code} {resp.text[:120]}")
    return ok


async def drive(api: httpx.AsyncClient, auth: dict, order: dict) -> bool:
    """Take one order from placed to ready-for-pickup."""
    order_id = order["id"]
    print(f"\n  order {order_id}  ({order['status']}, {order['payment_mode']})")

    if (
        order["payment_mode"] == "online"
        and order["payment_status"] != "paid"
    ):
        # The state machine refuses this, and no local webhook will ever mark it
        # paid. Say so plainly rather than let it fail three lines further down.
        print(
            "    -- skipped: an unpaid online order cannot be accepted.\n"
            "       Place the order as Cash on Delivery to exercise this flow."
        )
        return False

    if order["status"] == OrderStatus.PLACED.value:
        # accept moves PLACED -> ACCEPTED_BY_SHOP -> PREPARING in one call.
        if not await _step(
            api, auth, "accept", f"/api/v1/orders/{order_id}/accept"
        ):
            return False

    if not await _step(
        api,
        auth,
        "packing photo",
        f"/api/v1/orders/{order_id}/packing-photo",
        json={"photo_url": PLACEHOLDER_PHOTO},
    ):
        return False

    # This is the interesting one: it runs partner matching in-request, so by the
    # time it answers an offer either exists or provably could not be made.
    if not await _step(
        api, auth, "mark ready", f"/api/v1/orders/{order_id}/mark-ready"
    ):
        return False

    assignment = await assignment_for(order_id)
    if assignment is None:
        print(
            "    -- no rider was matched. The rider app must be online with a\n"
            "       location ping in the last 90s, within 6km of the shop."
        )
        return True

    print(
        f"    -> offered to partner {assignment['partner_id']}\n"
        f"       assignment {assignment['id']} "
        f"({assignment['offer_type']}, {assignment['status']})\n"
        f"       pickup code {assignment['pickup_code']}"
    )
    if assignment["status"] == "offered":
        print(
            "       The rider app should show the offer card within ~4s.\n"
            "       It lapses after 35s."
        )
    return True


async def run(args: argparse.Namespace) -> int:
    pending = (OrderStatus.PLACED.value, OrderStatus.PREPARING.value)

    if args.list:
        orders = await waiting_orders(pending)
        if not orders:
            print("Nothing waiting. Place an order in the customer app first.")
            return 0
        print(f"{len(orders)} order(s) waiting on the shop:\n")
        for order in orders:
            # "Rs" rather than the rupee sign: redirected stdout on Windows is
            # cp1252, which has no U+20B9 and raises rather than substituting.
            print(
                f"  {order['id']}  {order['status']:10s} "
                f"{order['payment_mode']}/{order['payment_status']:12s} "
                f"Rs {order['total_paise'] / 100:.0f}  {order['shop']}"
            )
        return 0

    async with (
        httpx.AsyncClient(base_url=args.supabase, timeout=20) as supabase,
        httpx.AsyncClient(base_url=args.api, timeout=30) as api,
    ):
        health = await api.get("/health")
        if health.status_code != 200:
            print(f"api /health -> {health.status_code}. Nothing else will work.")
            return 1

        try:
            token = await sign_in(supabase, args.anon_key)
        except RuntimeError as exc:
            print(f"shop owner login failed: {exc}")
            return 1
        auth = {"Authorization": f"Bearer {token}"}
        print(f"signed in as {OWNER_PHONE}")

        mine = await api.get("/api/v1/shops/mine", headers=auth)
        shop_id = mine.json().get("shop_id") if mine.status_code == 200 else None
        if shop_id:
            queue = await shop_queue(api, auth, shop_id)
            print(
                f"shop queue endpoint reports {len(queue)} order(s) "
                "needing attention"
            )

        seen: set[str] = set()
        while True:
            orders = [
                o for o in await waiting_orders(pending) if o["id"] not in seen
            ]
            for order in orders:
                seen.add(order["id"])
                await drive(api, auth, order)

            if not args.watch:
                if not orders:
                    print(
                        "\nNothing waiting. Place an order in the customer app "
                        "first (Cash on Delivery)."
                    )
                return 0

            if not orders:
                print(".", end="", flush=True)
            await asyncio.sleep(args.interval)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Drive the shop-side order steps the shop app cannot yet."
    )
    parser.add_argument("--supabase", default=DEFAULT_SUPABASE)
    parser.add_argument("--api", default=DEFAULT_API)
    parser.add_argument(
        "--anon-key",
        default=os.environ.get("SUPABASE_ANON_KEY", ""),
        help="local stack anon key; also read from SUPABASE_ANON_KEY",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="show what is waiting and exit, changing nothing",
    )
    parser.add_argument(
        "--watch",
        action="store_true",
        help="keep running and drive each new order as it is placed",
    )
    parser.add_argument("--interval", type=float, default=3.0)
    args = parser.parse_args()

    if not args.list and not args.anon_key:
        print(
            "Need the local anon key. Pass --anon-key or set SUPABASE_ANON_KEY.\n"
            "Get it with: npx supabase status -o env",
            file=sys.stderr,
        )
        raise SystemExit(2)

    try:
        raise SystemExit(asyncio.run(run(args)))
    except KeyboardInterrupt:
        print()
        raise SystemExit(130) from None


if __name__ == "__main__":
    main()
