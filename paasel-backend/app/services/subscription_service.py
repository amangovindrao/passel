"""Shop subscription lifecycle — trial, authorization, charging, suspension."""

from datetime import UTC, datetime, timedelta
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.enums import SubscriptionStatus
from app.models.entities import Shop, ShopSubscription, SubscriptionPlan
from app.services.razorpay_client import razorpay


async def create_trial(db: AsyncSession, shop_id: UUID) -> ShopSubscription:
    """Start a 30-day trial for a new shop."""
    # Default to Starter plan
    starter = await db.scalar(
        select(SubscriptionPlan).where(SubscriptionPlan.name == "Starter")
    )
    if not starter:
        raise ValueError("Starter plan not found — run migrations")

    now = datetime.now(UTC)
    subscription = ShopSubscription(
        shop_id=shop_id,
        plan_id=starter.id,
        is_trial=True,
        trial_start_date=now,
        trial_end_date=now + timedelta(days=30),
    )
    db.add(subscription)

    # Set shop subscription status
    shop = await db.get(Shop, shop_id)
    if shop:
        shop.subscription_status = SubscriptionStatus.TRIAL.value

    await db.flush()
    return subscription


async def authorize_subscription(
    db: AsyncSession, shop_id: UUID, plan_id: UUID | None = None
) -> dict:
    """Create a Razorpay Subscription for recurring billing mandate."""
    shop = await db.get(Shop, shop_id)
    if not shop:
        raise ValueError("Shop not found")

    sub = await db.scalar(
        select(ShopSubscription).where(ShopSubscription.shop_id == shop_id)
        .order_by(ShopSubscription.created_at.desc())
    )
    if not sub:
        raise ValueError("No subscription record found")

    plan = await db.get(SubscriptionPlan, plan_id or sub.plan_id)
    if not plan:
        raise ValueError("Plan not found")

    # Create Razorpay subscription
    # In production, plan_id would map to a Razorpay Plan ID
    rz_sub = await razorpay.create_subscription(
        plan_id=f"plan_{plan.name.lower()}",  # Razorpay plan ID
        notes={"shop_id": str(shop_id), "paasel_plan": plan.name},
    )

    sub.razorpay_subscription_id = rz_sub.get("id")
    await db.commit()

    return {
        "subscription_id": rz_sub.get("id"),
        "short_url": rz_sub.get("short_url"),
    }


async def handle_subscription_charged(
    db: AsyncSession, razorpay_subscription_id: str
) -> None:
    """Webhook: subscription.charged — extend active period."""
    sub = await db.scalar(
        select(ShopSubscription).where(
            ShopSubscription.razorpay_subscription_id == razorpay_subscription_id
        )
    )
    if not sub:
        return

    shop = await db.scalar(select(Shop).where(Shop.id == sub.shop_id))
    if shop:
        shop.subscription_status = SubscriptionStatus.ACTIVE.value
        shop.is_open = True  # Re-enable if was suspended

    sub.is_trial = False
    await db.commit()


async def check_trial_expiry(db: AsyncSession) -> list[UUID]:
    """Daily check: process expired trials.

    Returns list of shop_ids that were moved to past_due.
    """
    now = datetime.now(UTC)
    affected: list[UUID] = []

    # Find expired trials without authorized mandate
    expired_trials = (await db.execute(
        select(ShopSubscription)
        .join(Shop, Shop.id == ShopSubscription.shop_id)
        .where(
            ShopSubscription.is_trial == True,  # noqa: E712
            ShopSubscription.trial_end_date < now,
            ShopSubscription.razorpay_subscription_id.is_(None),
            Shop.subscription_status.in_([
                SubscriptionStatus.TRIAL.value,
                SubscriptionStatus.ACTIVE.value,
            ]),
        )
    )).scalars().all()

    for sub in expired_trials:
        shop = await db.get(Shop, sub.shop_id)
        if shop:
            shop.subscription_status = SubscriptionStatus.PAST_DUE.value
            affected.append(shop.id)

    await db.commit()
    return affected


async def check_grace_period_expiry(db: AsyncSession) -> list[UUID]:
    """Daily check: suspend shops past the 3-day grace period.

    Returns list of shop_ids that were suspended.
    """
    now = datetime.now(UTC)
    grace_cutoff = now - timedelta(days=3)
    suspended: list[UUID] = []

    # Find past_due shops whose trial ended > 3 days ago
    past_due_subs = (await db.execute(
        select(ShopSubscription)
        .join(Shop, Shop.id == ShopSubscription.shop_id)
        .where(
            Shop.subscription_status == SubscriptionStatus.PAST_DUE.value,
            ShopSubscription.trial_end_date < grace_cutoff,
            ShopSubscription.razorpay_subscription_id.is_(None),
        )
    )).scalars().all()

    for sub in past_due_subs:
        shop = await db.get(Shop, sub.shop_id)
        if shop:
            shop.subscription_status = SubscriptionStatus.SUSPENDED.value
            shop.is_open = False
            suspended.append(shop.id)

    await db.commit()
    return suspended
