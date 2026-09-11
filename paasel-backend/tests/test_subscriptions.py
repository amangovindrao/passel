"""Subscription lifecycle tests — trial to suspension."""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

from sqlalchemy import select

import pytest

from app.domain.enums import SubscriptionStatus
from app.models.entities import Shop, ShopSubscription, SubscriptionPlan, User
from app.services.subscription_service import (
    check_grace_period_expiry,
    check_trial_expiry,
    create_trial,
)


async def test_trial_to_past_due_to_suspended(db_session):
    """Fast-forward trial_end_date and prove grace-period-then-suspend sequence."""
    # Setup
    owner = User(id=uuid4(), phone="+919900300001", role="shop_owner")
    db_session.add(owner)
    await db_session.flush()

    # Migration 0001 seeds Starter/Growth/Pro, and plan names are unique — so
    # reuse the seeded row rather than inserting a duplicate.
    plan = await db_session.scalar(
        select(SubscriptionPlan).where(SubscriptionPlan.name == "Starter")
    )
    assert plan is not None, "subscription plans should be seeded by migration"

    shop = Shop(
        id=uuid4(), owner_id=owner.id, name="Trial Shop",
        category="grocery", location="SRID=4326;POINT(77.5946 12.9716)",
        delivery_radius_km=4, is_open=True,
        subscription_status=SubscriptionStatus.TRIAL.value,
    )
    db_session.add(shop)
    await db_session.flush()

    # Create trial
    sub = await create_trial(db_session, shop.id)
    assert sub.is_trial is True
    assert shop.subscription_status == SubscriptionStatus.TRIAL.value

    # Fast-forward: trial ended yesterday, no mandate authorized
    sub.trial_end_date = datetime.now(UTC) - timedelta(days=1)
    await db_session.flush()

    # Daily check: should move to past_due
    past_due_ids = await check_trial_expiry(db_session)
    assert shop.id in past_due_ids
    await db_session.refresh(shop)
    assert shop.subscription_status == SubscriptionStatus.PAST_DUE.value

    # Fast-forward: trial ended 4 days ago (past 3-day grace)
    sub.trial_end_date = datetime.now(UTC) - timedelta(days=4)
    await db_session.flush()

    # Daily check: should suspend
    suspended_ids = await check_grace_period_expiry(db_session)
    assert shop.id in suspended_ids
    await db_session.refresh(shop)
    assert shop.subscription_status == SubscriptionStatus.SUSPENDED.value
    assert shop.is_open is False
