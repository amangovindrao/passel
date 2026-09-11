"""Seed a small, coherent world so the apps have something to show.

An empty database means empty screens, which makes the apps look broken when
they are only bare. This creates one approved shop with a catalogue near a fixed
Bengaluru point, plus an approved rider so the delivery flow can be exercised.

Idempotent: run it as often as you like. Dev only.

    python scripts/seed_demo.py
    python scripts/seed_demo.py --lat 12.9716 --lng 77.5946
"""

from __future__ import annotations

import argparse
import asyncio
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from sqlalchemy import select

from app.core.database import SessionFactory
from app.domain.enums import KycStatus, SubscriptionStatus, UserRole
from app.models.entities import (
    DeliveryPartnerProfile,
    LiveLocation,
    Product,
    Shop,
    ShopOwnerProfile,
    ShopSubscription,
    SubscriptionPlan,
    User,
)

# Stable ids so re-running updates rather than duplicating.
SHOP_OWNER_ID = UUID("11111111-1111-4111-8111-111111111111")
SHOP_ID = UUID("22222222-2222-4222-8222-222222222222")
RIDER_ID = UUID("33333333-3333-4333-8333-333333333333")

# Deliberately NOT numbers listed in supabase/config.toml's test_otp block.
#
# Supabase assigns its own user id when someone logs in, and phone numbers are
# unique here. If the seed claimed a loggable number first, the real login would
# arrive with a different id and registration would fail with phone_in_use. So
# the demo rows own numbers nobody can log in as, and `--claim` hands them over
# to a real account afterwards.
SEED_OWNER_PHONE = "+919900009001"
SEED_RIDER_PHONE = "+919900009002"

# The two extra shops exist so the discovery list is a list rather than a single
# row, and so the ₹99 minimum and the per-km delivery fee are visible as real
# differences between nearby and further-away stores. They are not claimable —
# --claim hands over Corner Store, which is the one with the full catalogue.
SHOP_2_OWNER_ID = UUID("44444444-4444-4444-8444-444444444444")
SHOP_2_ID = UUID("55555555-5555-4555-8555-555555555555")
SEED_OWNER_2_PHONE = "+919900009003"

SHOP_3_OWNER_ID = UUID("66666666-6666-4666-8666-666666666666")
SHOP_3_ID = UUID("77777777-7777-4777-8777-777777777777")
SEED_OWNER_3_PHONE = "+919900009004"

CATALOGUE = [
    # Staples
    ("Toned Milk 500ml", 2700, "pack"),
    ("Full Cream Milk 1L", 7200, "pack"),
    ("Brown Bread", 4500, "loaf"),
    ("Pav Buns (6)", 3200, "pack"),
    ("Farm Eggs (6)", 6600, "tray"),
    ("Basmati Rice 1kg", 14500, "bag"),
    ("Toor Dal 1kg", 16800, "bag"),
    ("Atta 5kg", 27500, "bag"),
    # Dairy and fats
    ("Amul Butter 100g", 6200, "pack"),
    ("Paneer 200g", 9900, "pack"),
    ("Curd 400g", 4400, "cup"),
    ("Sunflower Oil 1L", 15900, "bottle"),
    # Fresh
    ("Bananas (dozen)", 5900, "dozen"),
    ("Tomatoes 1kg", 3800, "kg"),
    ("Onions 1kg", 4200, "kg"),
    ("Potatoes 1kg", 3600, "kg"),
    # Pantry
    ("Tea Leaves 250g", 15500, "pack"),
    ("Filter Coffee 200g", 21000, "pack"),
    ("Sugar 1kg", 5400, "bag"),
    ("Salt 1kg", 2600, "pack"),
    ("Maggi Noodles (4)", 5600, "pack"),
    ("Parle-G Biscuits", 1000, "pack"),
    # Household
    ("Dish Soap 500ml", 12500, "bottle"),
    ("Detergent 1kg", 18500, "pack"),
]

CATALOGUE_2 = [
    ("Alphonso Mangoes 1kg", 24900, "kg"),
    ("Pomegranate 500g", 13500, "pack"),
    ("Green Apples 1kg", 19900, "kg"),
    ("Sweet Lime 1kg", 8900, "kg"),
    ("Baby Spinach 250g", 4900, "pack"),
    ("Coriander Bunch", 1500, "bunch"),
    ("Green Chillies 100g", 1800, "pack"),
    ("Ginger 200g", 3400, "pack"),
    ("Capsicum 500g", 5600, "pack"),
    ("Cucumber 500g", 2900, "pack"),
    ("Curry Leaves", 1200, "bunch"),
    ("Tender Coconut", 4500, "piece"),
]

CATALOGUE_3 = [
    ("Paracetamol 500mg (10)", 3000, "strip"),
    ("ORS Sachet", 2200, "sachet"),
    ("Antiseptic Liquid 100ml", 8500, "bottle"),
    ("Band-Aid (10)", 4500, "pack"),
    ("Digital Thermometer", 24900, "piece"),
    ("Hand Sanitiser 200ml", 9900, "bottle"),
    ("Cough Syrup 100ml", 11500, "bottle"),
    ("Vitamin C Tablets (20)", 18500, "strip"),
]

# Each shop needs its own owner: shops.owner_id is unique.
EXTRA_SHOPS = [
    {
        "shop_id": SHOP_2_ID,
        "owner_id": SHOP_2_OWNER_ID,
        "phone": SEED_OWNER_2_PHONE,
        "owner_name": "Fresh & Daily Owner",
        "name": "Fresh & Daily",
        "category": "fruits_vegetables",
        # ~600m north-east, so it sorts second by distance and prices a
        # visibly different delivery fee.
        "offset": (0.0055, 0.0025),
        "catalogue": CATALOGUE_2,
    },
    {
        "shop_id": SHOP_3_ID,
        "owner_id": SHOP_3_OWNER_ID,
        "phone": SEED_OWNER_3_PHONE,
        "owner_name": "Anand Medicals Owner",
        "name": "Anand Medicals",
        "category": "pharmacy",
        "offset": (-0.0080, 0.0040),
        "catalogue": CATALOGUE_3,
    },
]


def point(lng: float, lat: float) -> str:
    return f"SRID=4326;POINT({lng} {lat})"


async def _stock(db, shop_id: UUID, catalogue: list[tuple]) -> int:
    """Adds any missing products. Returns how many were new.

    Matches on name rather than clearing and re-inserting, so re-running the seed
    does not orphan order_items that point at the old rows.
    """
    existing = set(
        (
            await db.execute(
                select(Product.name).where(Product.shop_id == shop_id)
            )
        )
        .scalars()
        .all()
    )
    added = 0
    for name, price_paise, unit in catalogue:
        if name in existing:
            continue
        db.add(
            Product(
                id=uuid4(),
                shop_id=shop_id,
                name=name,
                price_paise=price_paise,
                unit=unit,
                stock_status="available",
            )
        )
        added += 1
    await db.flush()
    return added


async def _seed_shop(db, spec: dict, *, lat: float, lng: float) -> int:
    """One approved, open shop with its own owner and catalogue."""
    owner = await db.get(User, spec["owner_id"])
    if owner is None:
        db.add(
            User(
                id=spec["owner_id"],
                phone=spec["phone"],
                role=UserRole.SHOP_OWNER.value,
            )
        )
        await db.flush()

    profile = await db.scalar(
        select(ShopOwnerProfile).where(
            ShopOwnerProfile.user_id == spec["owner_id"]
        )
    )
    if profile is None:
        profile = ShopOwnerProfile(
            user_id=spec["owner_id"], name=spec["owner_name"]
        )
        db.add(profile)
    profile.kyc_status = KycStatus.APPROVED.value
    await db.flush()

    d_lng, d_lat = spec["offset"]
    shop = await db.get(Shop, spec["shop_id"])
    if shop is None:
        shop = Shop(
            id=spec["shop_id"],
            owner_id=spec["owner_id"],
            name=spec["name"],
            category=spec["category"],
            location=point(lng + d_lng, lat + d_lat),
            delivery_radius_km=5,
            is_open=True,
            subscription_status=SubscriptionStatus.ACTIVE.value,
        )
        db.add(shop)
    else:
        shop.location = point(lng + d_lng, lat + d_lat)
        shop.is_open = True
        shop.subscription_status = SubscriptionStatus.ACTIVE.value
    await db.flush()

    return await _stock(db, spec["shop_id"], spec["catalogue"])


async def seed(lat: float, lng: float) -> None:
    async with SessionFactory() as db:
        # --- Shop owner, approved so the shop is visible ---
        owner = await db.get(User, SHOP_OWNER_ID)
        if owner is None:
            owner = User(
                id=SHOP_OWNER_ID,
                phone=SEED_OWNER_PHONE,
                role=UserRole.SHOP_OWNER.value,
            )
            db.add(owner)
            await db.flush()

        owner_profile = await db.scalar(
            select(ShopOwnerProfile).where(
                ShopOwnerProfile.user_id == SHOP_OWNER_ID
            )
        )
        if owner_profile is None:
            owner_profile = ShopOwnerProfile(
                user_id=SHOP_OWNER_ID, name="Demo Store Owner"
            )
            db.add(owner_profile)
        owner_profile.kyc_status = KycStatus.APPROVED.value
        await db.flush()

        # --- The shop itself, open and on a live subscription ---
        shop = await db.get(Shop, SHOP_ID)
        if shop is None:
            shop = Shop(
                id=SHOP_ID,
                owner_id=SHOP_OWNER_ID,
                name="Corner Store",
                category="grocery",
                location=point(lng, lat),
                delivery_radius_km=5,
                is_open=True,
                subscription_status=SubscriptionStatus.ACTIVE.value,
            )
            db.add(shop)
        else:
            shop.location = point(lng, lat)
            shop.is_open = True
            shop.subscription_status = SubscriptionStatus.ACTIVE.value
        await db.flush()

        # A trial subscription row, so the shop dashboard has something real.
        plan = await db.scalar(
            select(SubscriptionPlan).where(SubscriptionPlan.name == "Starter")
        )
        if plan is not None:
            existing_sub = await db.scalar(
                select(ShopSubscription).where(
                    ShopSubscription.shop_id == SHOP_ID
                )
            )
            if existing_sub is None:
                now = datetime.now(UTC)
                db.add(
                    ShopSubscription(
                        shop_id=SHOP_ID,
                        plan_id=plan.id,
                        is_trial=True,
                        trial_start_date=now,
                        trial_end_date=now + timedelta(days=30),
                    )
                )
                await db.flush()

        # --- Catalogue ---
        added = await _stock(db, SHOP_ID, CATALOGUE)

        # --- The other nearby shops ---
        extra_products = 0
        for spec in EXTRA_SHOPS:
            extra_products += await _seed_shop(db, spec, lat=lat, lng=lng)

        # --- An approved rider, online and pinging near the shop ---
        rider = await db.get(User, RIDER_ID)
        if rider is None:
            rider = User(
                id=RIDER_ID,
                phone=SEED_RIDER_PHONE,
                role=UserRole.DELIVERY_PARTNER.value,
            )
            db.add(rider)
            await db.flush()

        rider_profile = await db.scalar(
            select(DeliveryPartnerProfile).where(
                DeliveryPartnerProfile.user_id == RIDER_ID
            )
        )
        if rider_profile is None:
            rider_profile = DeliveryPartnerProfile(
                user_id=RIDER_ID, name="Demo Rider"
            )
            db.add(rider_profile)
        rider_profile.kyc_status = KycStatus.APPROVED.value
        rider_profile.vehicle_type = "bike"
        rider_profile.vehicle_number = "KA01AB1234"
        rider_profile.id_proof_url = "https://storage.example.com/demo_id.jpg"
        rider_profile.is_online = True
        await db.flush()

        # Fresh ping ~400m from the shop, so matching can actually see them.
        live = await db.get(LiveLocation, RIDER_ID)
        if live is None:
            db.add(
                LiveLocation(
                    partner_id=RIDER_ID,
                    location=point(lng + 0.004, lat),
                    updated_at=datetime.now(UTC),
                )
            )
        else:
            live.location = point(lng + 0.004, lat)
            live.updated_at = datetime.now(UTC)

        await db.commit()

    total = len(CATALOGUE) + sum(len(s["catalogue"]) for s in EXTRA_SHOPS)
    print(f"shop          : Corner Store @ {lat}, {lng} (open, approved)")
    for spec in EXTRA_SHOPS:
        print(f"                {spec['name']} ({spec['category']}, nearby)")
    print(
        f"products      : {total} across 3 shops "
        f"({added + extra_products} new)"
    )
    print("rider         : Demo Rider (approved, online, ~400m away)")
    print()
    print("Log in on the phone with these — OTP is always 123456:")
    print("  customer        9900000001")
    print("  shop owner      9900000002")
    print("  delivery rider  9900000003")
    print()
    print("The demo shop and rider above are held by placeholder numbers so")
    print("they never collide with a real login. To hand them over:")
    print("  python scripts/seed_demo.py --claim +919900000002")
    print("  python scripts/seed_demo.py --approve-rider +919900000003")


async def claim(phone: str) -> None:
    """Hand the demo shop to a real, already-registered shop owner.

    Log in on the phone first so the account exists, then run this. The shop and
    its catalogue move across, so the shop app opens on a populated store
    instead of an empty first-run state.
    """
    normalised = phone if phone.startswith("+") else f"+{phone}"

    async with SessionFactory() as db:
        user = await db.scalar(select(User).where(User.phone == normalised))
        if user is None:
            print(f"No account for {normalised}. Log in on the app first.")
            return
        if user.role != UserRole.SHOP_OWNER.value:
            print(f"{normalised} is a {user.role}, not a shop owner.")
            return

        shop = await db.get(Shop, SHOP_ID)
        if shop is None:
            print("Demo shop not found. Run without --claim first.")
            return

        # One shop per owner is enforced by a unique constraint, so a shop they
        # already created has to go before this one can move over.
        theirs = await db.scalar(
            select(Shop).where(Shop.owner_id == user.id, Shop.id != SHOP_ID)
        )
        if theirs is not None:
            print(
                f"{normalised} already owns '{theirs.name}'. "
                "Delete it first, or test with a different number."
            )
            return

        profile = await db.scalar(
            select(ShopOwnerProfile).where(ShopOwnerProfile.user_id == user.id)
        )
        if profile is not None:
            profile.kyc_status = KycStatus.APPROVED.value

        shop.owner_id = user.id
        await db.commit()

    print(f"'Corner Store' and its {len(CATALOGUE)} products now belong to {normalised}")
    print("That account is also KYC-approved, so the dashboard opens directly.")


async def approve_rider(phone: str) -> None:
    """Approve a real rider's KYC so they can go online without an admin UI."""
    normalised = phone if phone.startswith("+") else f"+{phone}"

    async with SessionFactory() as db:
        user = await db.scalar(select(User).where(User.phone == normalised))
        if user is None:
            print(f"No account for {normalised}. Log in on the app first.")
            return

        profile = await db.scalar(
            select(DeliveryPartnerProfile).where(
                DeliveryPartnerProfile.user_id == user.id
            )
        )
        if profile is None:
            print(f"{normalised} has no delivery partner profile.")
            return

        profile.kyc_status = KycStatus.APPROVED.value
        if not profile.vehicle_type:
            profile.vehicle_type = "bike"
            profile.vehicle_number = "KA01AB1234"
        if not profile.id_proof_url:
            profile.id_proof_url = "https://storage.example.com/demo_id.jpg"
        await db.commit()

    print(f"{normalised} is KYC-approved and can go online.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--lat",
        type=float,
        default=12.9716,
        help="shop latitude (default: central Bengaluru)",
    )
    parser.add_argument("--lng", type=float, default=77.5946)
    parser.add_argument(
        "--claim",
        metavar="PHONE",
        help="give the demo shop to this already-registered shop owner",
    )
    parser.add_argument(
        "--approve-rider",
        metavar="PHONE",
        help="approve this already-registered rider's KYC",
    )
    args = parser.parse_args()

    if args.claim:
        asyncio.run(claim(args.claim))
    elif args.approve_rider:
        asyncio.run(approve_rider(args.approve_rider))
    else:
        asyncio.run(seed(args.lat, args.lng))


if __name__ == "__main__":
    main()
