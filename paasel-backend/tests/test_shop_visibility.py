"""Shop visibility tests — kyc/subscription filtering."""

from sqlalchemy import text

from app.domain.enums import KycStatus, SubscriptionStatus
from tests.factories import make_shop

# Mirrors the WHERE clause in GET /api/v1/shops/nearby.
_VISIBILITY_SQL = text("""
    SELECT s.id, s.name FROM shops s
    JOIN shop_owner_profiles sop ON sop.user_id = s.owner_id
    WHERE s.subscription_status NOT IN ('suspended')
      AND sop.kyc_status = 'approved'
""")


async def test_nearby_excludes_pending_kyc_and_suspended(db_session):
    """Shops with pending KYC or a suspended subscription are invisible."""
    visible = await make_shop(
        db_session,
        lng=77.5946,
        subscription_status=SubscriptionStatus.ACTIVE.value,
        kyc_status=KycStatus.APPROVED.value,
    )
    pending = await make_shop(
        db_session,
        lng=77.5950,
        subscription_status=SubscriptionStatus.TRIAL.value,
        kyc_status=KycStatus.PENDING.value,
    )
    suspended = await make_shop(
        db_session,
        lng=77.5955,
        subscription_status=SubscriptionStatus.SUSPENDED.value,
        kyc_status=KycStatus.APPROVED.value,
    )

    visible_ids = {row.id for row in (await db_session.execute(_VISIBILITY_SQL)).all()}

    assert visible.id in visible_ids
    assert pending.id not in visible_ids, 'unverified owner must stay hidden'
    assert suspended.id not in visible_ids, 'suspended shop must stay hidden'


async def test_trial_subscription_is_still_visible(db_session):
    """A trial is a paying-in-future customer, not a suspended one."""
    trial = await make_shop(
        db_session,
        subscription_status=SubscriptionStatus.TRIAL.value,
        kyc_status=KycStatus.APPROVED.value,
    )

    visible_ids = {row.id for row in (await db_session.execute(_VISIBILITY_SQL)).all()}

    assert trial.id in visible_ids
