"""Partner matching and batching tests."""

from uuid import uuid4

from app.domain.enums import AssignmentStatus, OrderStatus
from app.services.partner_matching import find_nearest_partner, try_batch_tier1
from tests.factories import (
    make_assignment,
    make_order,
    make_partner,
    make_shop,
)


async def test_nearest_partner_selected_first(db_session):
    """Three partners at different distances; nearest is offered first."""
    shop = await make_shop(db_session)

    partner_a = await make_partner(db_session, lng=77.5990)  # ~500m east
    await make_partner(db_session, lng=77.6100)  # ~1500m east
    await make_partner(db_session, lng=77.6200)  # ~2500m east

    order = await make_order(
        db_session, shop=shop, status=OrderStatus.READY_FOR_PICKUP
    )

    assert await find_nearest_partner(db_session, order) == partner_a.id


async def test_excluded_partners_skipped(db_session):
    """When partner A is excluded, partner B is selected."""
    shop = await make_shop(db_session)

    partner_a = await make_partner(db_session, lng=77.5960)
    partner_b = await make_partner(db_session, lng=77.6050)

    order = await make_order(
        db_session,
        shop=shop,
        status=OrderStatus.READY_FOR_PICKUP,
        payment_mode='cod',
    )

    result = await find_nearest_partner(
        db_session, order, excluded_partner_ids=[partner_a.id]
    )
    assert result == partner_b.id


async def test_batch_tier1_attaches_to_existing_trip(db_session):
    """Second order at same shop attaches to existing partner's trip."""
    shop = await make_shop(db_session)
    partner = await make_partner(db_session, lng=77.5960)

    existing_order = await make_order(
        db_session, shop=shop, status=OrderStatus.PARTNER_ASSIGNED
    )
    trip_id = uuid4()
    await make_assignment(
        db_session,
        existing_order,
        partner,
        trip_id=trip_id,
        pickup_code='1111',
        accepted=True,
    )

    new_order = await make_order(
        db_session,
        shop=shop,
        status=OrderStatus.READY_FOR_PICKUP,
        payment_mode='cod',
    )

    batch = await try_batch_tier1(db_session, new_order)

    assert batch is not None
    assert batch.trip_id == trip_id
    assert batch.partner_id == partner.id
    assert len(batch.pickup_code) == 4
    # Tier 1 is consent-free — the partner has not picked up yet and it is the
    # same physical stop — so the assignment lands already accepted rather than
    # sitting as an offer nobody will ever answer.
    assert batch.status == AssignmentStatus.ACCEPTED.value
    assert batch.accepted_at is not None
