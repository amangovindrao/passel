"""Prove a rider can actually be handed an offer, over HTTP, as the three users.

The offer flow has more moving parts than any other path in Paasel and every one
of them can fail quietly: a rider who is online but not pinging is invisible to
matching, an online order can never be accepted, the packing photo is a guard,
and matching runs inside mark-ready rather than in a worker. So this walks the
whole chain with real tokens and reports where it stops.

It ends on the endpoint the rider app polls. If the last line says an offer is
waiting, the offer card will appear on the phone.

    python scripts/e2e_offer.py --anon-key <key>
    python scripts/e2e_offer.py --anon-key <key> --api http://10.112.197.71:8000 \
        --supabase http://10.112.197.71:54321

Dev only — it places a real order and drives it to ready-for-pickup.
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
from uuid import uuid4

import httpx
from sqlalchemy import select

from app.core.database import SessionFactory
from app.domain.enums import OrderStatus
from app.models.entities import DeliveryAssignment, Order, User

DEFAULT_SUPABASE = "http://127.0.0.1:54321"
DEFAULT_API = "http://127.0.0.1:8000"
OTP = "123456"

CUSTOMER = "+919900000001"
OWNER = "+919900000002"
RIDER = "+919900000003"

# The seeded shop sits here; the rider needs to be inside 6km of it and the
# drop-off inside the delivery radius.
SHOP_LAT, SHOP_LNG = 12.9716, 77.5946
RIDER_LAT, RIDER_LNG = 12.9720, 77.5990
DROP_LAT, DROP_LNG = 12.9750, 77.6050

PLACEHOLDER_PHOTO = "https://placehold.co/600x400?text=packed"


class Step:
    """Prints each call as it happens, and remembers whether anything failed."""

    def __init__(self) -> None:
        self.failures = 0

    def record(self, label: str, resp: httpx.Response, *, ok: int = 200) -> bool:
        good = resp.status_code == ok
        if not good:
            self.failures += 1
        marker = "ok " if good else "ERR"
        print(f"  {marker} {label:34s} {resp.status_code} {resp.text[:110]}")
        return good


async def close_out_rider_trips() -> int:
    """Finish anything the rider is still carrying, so a fresh offer can happen.

    Without this a second run does not produce an offer at all — and correctly
    so. Tier 1 batching sees the rider already assigned to an order at this shop
    and attaches the new one to that trip without asking, which is the whole
    point of Tier 1. Useful behaviour, wrong thing to be measuring here.

    Orders are marked COMPLETED rather than deleted: terminal states drop out of
    both the Tier 1 lookup and the per-trip order count, and nothing is lost.
    """
    async with SessionFactory() as db:
        rider = await db.scalar(select(User).where(User.phone == RIDER))
        if rider is None:
            return 0

        rows = (
            await db.execute(
                select(Order)
                .join(
                    DeliveryAssignment,
                    DeliveryAssignment.order_id == Order.id,
                )
                .where(
                    DeliveryAssignment.partner_id == rider.id,
                    Order.status.notin_([
                        OrderStatus.DELIVERED.value,
                        OrderStatus.COMPLETED.value,
                        OrderStatus.CANCELLED_BY_CUSTOMER.value,
                        OrderStatus.CANCELLED_BY_SHOP.value,
                        OrderStatus.CANCELLED_ITEM_UNAVAILABLE.value,
                        OrderStatus.REJECTED_BY_SHOP.value,
                    ]),
                )
            )
        ).scalars().all()

        for order in rows:
            order.status = OrderStatus.COMPLETED.value
        await db.commit()
        return len(rows)


async def sign_in(supabase: httpx.AsyncClient, anon_key: str, phone: str) -> str:
    headers = {"apikey": anon_key, "Content-Type": "application/json"}
    await supabase.post("/auth/v1/otp", headers=headers, json={"phone": phone})
    verified = await supabase.post(
        "/auth/v1/verify",
        headers=headers,
        json={"type": "sms", "phone": phone, "token": OTP},
    )
    token = verified.json().get("access_token")
    if not token:
        raise RuntimeError(f"login failed for {phone}: {verified.text}")
    return token


async def run(args: argparse.Namespace) -> int:
    step = Step()

    async with (
        httpx.AsyncClient(base_url=args.supabase, timeout=20) as supabase,
        httpx.AsyncClient(base_url=args.api, timeout=30) as api,
    ):
        health = await api.get("/health")
        if not step.record("api /health", health):
            return 1

        print("\n--- sign in ---")
        try:
            tokens = {
                "customer": await sign_in(supabase, args.anon_key, CUSTOMER),
                "owner": await sign_in(supabase, args.anon_key, OWNER),
                "rider": await sign_in(supabase, args.anon_key, RIDER),
            }
        except RuntimeError as exc:
            print(f"  ERR {exc}")
            return 1
        auth = {k: {"Authorization": f"Bearer {v}"} for k, v in tokens.items()}
        print("  ok  all three signed in")

        if args.reset:
            closed = await close_out_rider_trips()
            print(f"\n--- reset: closed out {closed} in-flight order(s) ---")

        # --- The rider has to be genuinely available, not just flagged online.
        print("\n--- rider goes on duty ---")
        step.record(
            "online",
            await api.post(
                "/api/v1/delivery-partners/online",
                headers=auth["rider"],
                json={"is_online": True},
            ),
        )
        # Matching ignores a partner whose last ping is over 90s old, so this is
        # not optional bookkeeping — without it there is nobody to offer to.
        step.record(
            "location ping",
            await api.post(
                "/api/v1/delivery-partners/location",
                headers=auth["rider"],
                json={"lat": RIDER_LAT, "lng": RIDER_LNG},
            ),
        )

        # --- Customer side.
        print("\n--- customer places a COD order ---")
        nearby = await api.get(
            "/api/v1/shops/nearby",
            headers=auth["customer"],
            params={"lat": SHOP_LAT, "lng": SHOP_LNG},
        )
        if not step.record("shops/nearby", nearby) or not nearby.json():
            print("  no shop nearby. Run: python scripts/seed_demo.py")
            return 1
        shop_id = nearby.json()[0]["id"]

        detail = await api.get(
            f"/api/v1/shops/{shop_id}", headers=auth["customer"]
        )
        if not step.record("shop detail", detail):
            return 1
        products = [
            p
            for group in detail.json()["products"].values()
            for p in group
            if p["stock_status"] == "available"
        ]
        if not products:
            print("  the shop has no available products.")
            return 1
        # Clear the ₹99 minimum with the dearest single item, so the order needs
        # no arithmetic to reason about.
        product = max(products, key=lambda p: p["price_paise"])
        qty = 1 if product["price_paise"] >= 9900 else (9900 // product["price_paise"]) + 1
        # "Rs" rather than the rupee sign: this gets redirected to a file on
        # Windows, where stdout is cp1252 and U+20B9 is simply not in it.
        print(
            f"      using {product['name']} x{qty} "
            f"= Rs {product['price_paise'] * qty / 100:.0f}"
        )

        address = await api.post(
            "/api/v1/addresses",
            headers=auth["customer"],
            json={
                "label": f"Test drop {uuid4().hex[:6]}",
                "lat": DROP_LAT,
                "lng": DROP_LNG,
                "address_text": "Test drop-off",
            },
        )
        if not step.record("create address", address):
            return 1
        address_id = address.json()["id"]

        placed = await api.post(
            "/api/v1/orders",
            headers=auth["customer"],
            json={
                "shop_id": shop_id,
                "address_id": address_id,
                "items": [{"product_id": product["id"], "qty": qty}],
                # COD on purpose: an online order cannot be accepted by the shop
                # until a Razorpay webhook marks it paid, and no such webhook
                # will ever arrive at a laptop.
                "payment_mode": "cod",
                "idempotency_key": str(uuid4()),
            },
        )
        if not step.record("place order (cod)", placed):
            return 1
        order_id = placed.json()["order_id"]
        print(f"      order {order_id}")

        # --- Shop side. These are the taps the shop app cannot do yet.
        print("\n--- shop accepts, packs, hands off ---")
        if not step.record(
            "accept",
            await api.post(
                f"/api/v1/orders/{order_id}/accept", headers=auth["owner"]
            ),
        ):
            return 1
        if not step.record(
            "packing photo",
            await api.post(
                f"/api/v1/orders/{order_id}/packing-photo",
                headers=auth["owner"],
                json={"photo_url": PLACEHOLDER_PHOTO},
            ),
        ):
            return 1
        # Matching runs inside this call, so by the time it answers an offer
        # either exists or provably could not be made.
        ready = await api.post(
            f"/api/v1/orders/{order_id}/mark-ready", headers=auth["owner"]
        )
        if not step.record("mark ready (runs matching)", ready):
            return 1
        assignment_id = ready.json().get("assignment_id")
        if not assignment_id:
            print(
                "\n  No rider was matched. The rider must be online with a ping\n"
                "  inside 90s and within 6km of the shop."
            )
            return 1
        print(f"      assignment {assignment_id}")

        # Tier 1 attaches to a trip the rider is already on, deliberately without
        # asking, so there is no offer to poll for. Correct behaviour, different
        # path — say which one happened rather than report a false failure.
        async with SessionFactory() as db:
            created = await db.get(DeliveryAssignment, assignment_id)
            batched = created is not None and created.status == "accepted"
        if batched:
            print(
                "\n  Tier 1 batching: the rider was already picking up at this\n"
                "  shop, so this order joined that trip with no offer made.\n"
                "  Re-run with --reset to exercise the fresh-offer path."
            )
            return 0

        # --- The endpoint the rider app polls. This is the whole point.
        print("\n--- rider polls for the offer ---")
        offer_resp = await api.get(
            "/api/v1/delivery-partners/me/offer", headers=auth["rider"]
        )
        if not step.record("me/offer", offer_resp):
            return 1
        offer = offer_resp.json()["offer"]
        if offer is None:
            print("\n  The offer endpoint returned nothing. The card will not show.")
            return 1
        print(
            f"      {offer['shop_name']}, {offer['item_count']} items, "
            f"Rs {offer['delivery_fee_paise'] / 100:.0f}, "
            f"{offer['distance_to_shop_m']}m away, "
            f"{offer['window_seconds']}s left ({offer['offer_type']})"
        )
        if offer["assignment_id"] != assignment_id:
            print("  ERR the polled offer is not the assignment just created")
            step.failures += 1

        if args.accept:
            print("\n--- rider accepts ---")
            step.record(
                "accept assignment",
                await api.post(
                    f"/api/v1/orders/assignments/{assignment_id}/accept",
                    headers=auth["rider"],
                ),
            )
            gone = await api.get(
                "/api/v1/delivery-partners/me/offer", headers=auth["rider"]
            )
            step.record("me/offer after accept", gone)
            if gone.json()["offer"] is not None:
                print("  ERR an accepted offer is still being served")
                step.failures += 1

    print()
    if step.failures:
        print(f"{step.failures} step(s) failed.")
        return 1
    print(
        "Offer flow works end to end. A rider signed in on the phone and online\n"
        "will see this offer card within about four seconds."
    )
    return 0


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--supabase", default=DEFAULT_SUPABASE)
    parser.add_argument("--api", default=DEFAULT_API)
    parser.add_argument(
        "--anon-key", default=os.environ.get("SUPABASE_ANON_KEY", "")
    )
    parser.add_argument(
        "--accept",
        action="store_true",
        help="also accept the offer, and check it stops being served",
    )
    parser.add_argument(
        "--reset",
        action="store_true",
        help=(
            "mark the rider's in-flight orders COMPLETED first, so Tier 1 "
            "batching does not absorb the new one"
        ),
    )
    args = parser.parse_args()

    if not args.anon_key:
        print(
            "Need the local anon key. Pass --anon-key or set SUPABASE_ANON_KEY.",
            file=sys.stderr,
        )
        raise SystemExit(2)

    raise SystemExit(asyncio.run(run(args)))


if __name__ == "__main__":
    main()
