"""Rider availability: ping freshness, stale-online sweep, offline blocking."""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

from sqlalchemy import select, text

from app.domain.enums import AssignmentStatus, KycStatus, OrderStatus
from app.models.entities import (
    Address,
    DeliveryAssignment,
    DeliveryPartnerProfile,
    LiveLocation,
    Order,
    Shop,
    User,
)
from app.services.batch_offers import (
    STALE_ONLINE_THRESHOLD_SECONDS,
    active_accepted_assignment,
)
from app.services.partner_matching import find_nearest_partner

# Bengaluru city centre — the same anchor the other matching tests use.
_SHOP_LNG = 77.5946
_SHOP_LAT = 12.9716


# --- Fixtures built by hand ---
#
# These models carry raw ForeignKey columns with no relationship(), so
# SQLAlchemy's unit of work cannot work out that a User must be inserted before
# the rows pointing at it. Every helper therefore flushes its parent before
# adding dependents.


async def _user(db, role: str = 'delivery_partner') -> User:
    user = User(
        id=uuid4(), phone=f'+91{uuid4().int % 10**10:010d}', role=role
    )
    db.add(user)
    await db.flush()
    return user


async def _shop(db) -> Shop:
    owner = await _user(db, 'shop_owner')
    shop = Shop(
        id=uuid4(),
        owner_id=owner.id,
        name='Test Shop',
        category='grocery',
        location=f'SRID=4326;POINT({_SHOP_LNG} {_SHOP_LAT})',
        delivery_radius_km=4,
        is_open=True,
        subscription_status='active',
    )
    db.add(shop)
    await db.flush()
    return shop


async def _online_partner(db, *, ping_age_seconds: int, lng=77.5990) -> User:
    """An online partner whose last ping is `ping_age_seconds` old."""
    partner = await _user(db)
    db.add(
        DeliveryPartnerProfile(
            user_id=partner.id,
            name='Rider',
            vehicle_type='bike',
            is_online=True,
            kyc_status=KycStatus.APPROVED.value,
        )
    )
    db.add(
        LiveLocation(
            partner_id=partner.id,
            location=f'SRID=4326;POINT({lng} {_SHOP_LAT})',
            updated_at=datetime.now(UTC) - timedelta(seconds=ping_age_seconds),
        )
    )
    await db.flush()
    return partner


async def _order(
    db,
    shop: Shop,
    *,
    status: OrderStatus = OrderStatus.READY_FOR_PICKUP,
    with_address: bool = False,
) -> Order:
    customer = await _user(db, 'customer')

    address_id = None
    if with_address:
        address = Address(
            id=uuid4(),
            customer_id=customer.id,
            label='Home',
            location='SRID=4326;POINT(77.6050 12.9750)',
            address_text='Somewhere',
        )
        db.add(address)
        await db.flush()
        address_id = address.id

    order = Order(
        id=uuid4(),
        customer_id=customer.id,
        shop_id=shop.id,
        delivery_address_id=address_id,
        status=status.value,
        item_total_paise=50000,
        delivery_fee_paise=3000,
        payment_mode='cod',
    )
    db.add(order)
    await db.flush()
    return order


# --- FIX 1: matching requires a recent ping ---


async def test_matching_skips_partner_with_stale_ping(db_session):
    """is_online=true is not enough — a partner who stopped pinging is invisible.

    This is the killed-app / dead-battery / lost-signal case: the flag is still
    true because nothing got the chance to flip it off.
    """
    shop = await _shop(db_session)
    # 200s > the 90s freshness window, and well inside the search radius.
    await _online_partner(db_session, ping_age_seconds=200)
    order = await _order(db_session, shop)

    assert await find_nearest_partner(db_session, order) is None


async def test_matching_accepts_partner_with_fresh_ping(db_session):
    """The same partner, pinging normally, is matchable."""
    shop = await _shop(db_session)
    partner = await _online_partner(db_session, ping_age_seconds=10)
    order = await _order(db_session, shop)

    assert await find_nearest_partner(db_session, order) == partner.id


async def test_matching_prefers_fresh_over_nearer_but_stale(db_session):
    """A nearer partner who went dark loses to a further one still pinging."""
    shop = await _shop(db_session)
    # Stale but almost on top of the shop.
    await _online_partner(db_session, ping_age_seconds=300, lng=77.5950)
    # Fresh but ~1.5km away.
    fresh = await _online_partner(db_session, ping_age_seconds=5, lng=77.6100)
    order = await _order(db_session, shop)

    assert await find_nearest_partner(db_session, order) == fresh.id


async def test_matching_ignores_offline_partner_even_when_pinging(db_session):
    """A fresh ping does not override an explicit offline flag."""
    shop = await _shop(db_session)
    partner = await _online_partner(db_session, ping_age_seconds=5)
    profile = await db_session.scalar(
        select(DeliveryPartnerProfile).where(
            DeliveryPartnerProfile.user_id == partner.id
        )
    )
    profile.is_online = False
    await db_session.flush()
    order = await _order(db_session, shop)

    assert await find_nearest_partner(db_session, order) is None


# --- FIX 2: stale-online sweep ---


async def _run_sweep(db) -> set[str]:
    """The sweep statement from paasel.stale_online_sweep, run inline.

    The Celery task opens its own session, which would sit outside this test's
    transaction, so the statement itself is what gets exercised here.
    """
    result = await db.execute(
        text("""
            UPDATE delivery_partner_profiles dp
            SET is_online = false
            WHERE dp.is_online = true
              AND NOT EXISTS (
                SELECT 1 FROM live_locations ll
                WHERE ll.partner_id = dp.user_id
                  AND ll.updated_at > now() - make_interval(secs => :threshold)
              )
            RETURNING dp.user_id
        """),
        {'threshold': STALE_ONLINE_THRESHOLD_SECONDS},
    )
    return {str(row[0]) for row in result.all()}


async def _is_online(db, partner_id) -> bool:
    """Read is_online straight from the row, past any ORM caching."""
    db.expire_all()
    return await db.scalar(
        select(DeliveryPartnerProfile.is_online).where(
            DeliveryPartnerProfile.user_id == partner_id
        )
    )


async def test_sweep_forces_offline_after_ten_minutes(db_session):
    """No ping for 10+ minutes means the online flag is wrong. Fix it."""
    partner = await _online_partner(db_session, ping_age_seconds=15 * 60)

    swept = await _run_sweep(db_session)

    assert str(partner.id) in swept
    assert await _is_online(db_session, partner.id) is False


async def test_sweep_leaves_recently_active_partner_online(db_session):
    """A partner pinging normally must not be knocked offline."""
    partner = await _online_partner(db_session, ping_age_seconds=30)

    swept = await _run_sweep(db_session)

    assert str(partner.id) not in swept
    assert await _is_online(db_session, partner.id) is True


async def test_sweep_forces_offline_when_partner_never_pinged(db_session):
    """Online with no live_locations row at all is also stale."""
    partner = await _user(db_session)
    db_session.add(
        DeliveryPartnerProfile(
            user_id=partner.id,
            name='Never pinged',
            vehicle_type='bicycle',
            is_online=True,
            kyc_status=KycStatus.APPROVED.value,
        )
    )
    await db_session.flush()

    swept = await _run_sweep(db_session)

    assert str(partner.id) in swept
    assert await _is_online(db_session, partner.id) is False


async def test_sweep_ignores_partners_already_offline(db_session):
    """Nothing to do for someone who is already offline."""
    partner = await _user(db_session)
    db_session.add(
        DeliveryPartnerProfile(
            user_id=partner.id,
            name='Off duty',
            vehicle_type='bicycle',
            is_online=False,
            kyc_status=KycStatus.APPROVED.value,
        )
    )
    await db_session.flush()

    swept = await _run_sweep(db_session)

    assert str(partner.id) not in swept


# --- Going offline mid-delivery ---


async def test_active_accepted_assignment_blocks_going_offline(db_session):
    """An accepted, undelivered assignment is what produces the 409."""
    shop = await _shop(db_session)
    partner = await _online_partner(db_session, ping_age_seconds=5)
    order = await _order(
        db_session,
        shop,
        status=OrderStatus.OUT_FOR_DELIVERY,
        with_address=True,
    )

    db_session.add(
        DeliveryAssignment(
            order_id=order.id,
            partner_id=partner.id,
            trip_id=uuid4(),
            pickup_code='4321',
            status=AssignmentStatus.ACCEPTED.value,
            accepted_at=datetime.now(UTC),
        )
    )
    await db_session.flush()

    assert await active_accepted_assignment(db_session, partner.id) is not None


async def test_delivered_order_no_longer_blocks_going_offline(db_session):
    """Once the order is DELIVERED the same assignment stops blocking."""
    shop = await _shop(db_session)
    partner = await _online_partner(db_session, ping_age_seconds=5)
    order = await _order(db_session, shop, status=OrderStatus.DELIVERED)

    db_session.add(
        DeliveryAssignment(
            order_id=order.id,
            partner_id=partner.id,
            trip_id=uuid4(),
            pickup_code='4321',
            status=AssignmentStatus.ACCEPTED.value,
            accepted_at=datetime.now(UTC),
        )
    )
    await db_session.flush()

    assert await active_accepted_assignment(db_session, partner.id) is None


async def test_unanswered_offer_does_not_block_going_offline(db_session):
    """An offer they never answered is not an active delivery."""
    shop = await _shop(db_session)
    partner = await _online_partner(db_session, ping_age_seconds=5)
    order = await _order(db_session, shop)

    db_session.add(
        DeliveryAssignment(
            order_id=order.id,
            partner_id=partner.id,
            trip_id=uuid4(),
            pickup_code='4321',
            status=AssignmentStatus.OFFERED.value,
        )
    )
    await db_session.flush()

    assert await active_accepted_assignment(db_session, partner.id) is None
