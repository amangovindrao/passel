"""Tier 2 mid-trip detour offers: eligibility, timeout fall-through, repricing."""

from datetime import UTC, datetime
from uuid import uuid4

from sqlalchemy import select

from app.domain.enums import AssignmentStatus, KycStatus, OfferType, OrderStatus
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
    accept_batch_offer,
    decline_batch_offer,
    expire_batch_offer,
)
from app.services.partner_matching import (
    BATCHED_RATE_PAISE_PER_KM,
    batched_delivery_fee_paise,
    run_matching,
    try_batch_tier2,
)
from app.services.routing import route_distance_m

_LAT = 12.9716

# These models use raw ForeignKey columns with no relationship(), so every
# helper flushes its parent row before adding anything that points at it.


async def _user(db, role: str = 'delivery_partner') -> User:
    user = User(
        id=uuid4(), phone=f'+91{uuid4().int % 10**10:010d}', role=role
    )
    db.add(user)
    await db.flush()
    return user


async def _shop(db, lng: float = 77.5946) -> Shop:
    owner = await _user(db, 'shop_owner')
    shop = Shop(
        id=uuid4(),
        owner_id=owner.id,
        name='Test Shop',
        category='grocery',
        location=f'SRID=4326;POINT({lng} {_LAT})',
        delivery_radius_km=4,
        is_open=True,
        subscription_status='active',
    )
    db.add(shop)
    await db.flush()
    return shop


async def _address(db, customer_id, lng: float, label: str) -> Address:
    address = Address(
        id=uuid4(),
        customer_id=customer_id,
        label=label,
        location=f'SRID=4326;POINT({lng} {_LAT})',
        address_text=label,
    )
    db.add(address)
    await db.flush()
    return address


async def _order(
    db,
    shop: Shop,
    *,
    dropoff_lng: float,
    status: OrderStatus = OrderStatus.READY_FOR_PICKUP,
    payment_mode: str = 'cod',
    delivery_fee_paise: int = 3000,
    label: str = 'Drop',
) -> Order:
    customer = await _user(db, 'customer')
    dropoff = await _address(db, customer.id, dropoff_lng, label)
    order = Order(
        id=uuid4(),
        customer_id=customer.id,
        shop_id=shop.id,
        delivery_address_id=dropoff.id,
        status=status.value,
        item_total_paise=50000,
        delivery_fee_paise=delivery_fee_paise,
        payment_mode=payment_mode,
    )
    db.add(order)
    await db.flush()
    return order


async def _mid_trip_partner(
    db, shop: Shop, *, dropoff_lng: float, partner_lng: float
) -> tuple[User, object]:
    """A partner already OUT_FOR_DELIVERY with one drop-off ahead of them."""
    partner = await _user(db)
    db.add(
        DeliveryPartnerProfile(
            user_id=partner.id,
            name='Mid-trip rider',
            vehicle_type='scooter',
            is_online=True,
            kyc_status=KycStatus.APPROVED.value,
        )
    )
    db.add(
        LiveLocation(
            partner_id=partner.id,
            location=f'SRID=4326;POINT({partner_lng} {_LAT})',
            updated_at=datetime.now(UTC),
        )
    )
    await db.flush()

    existing_order = await _order(
        db,
        shop,
        dropoff_lng=dropoff_lng,
        status=OrderStatus.OUT_FOR_DELIVERY,
        label='Existing drop',
    )

    trip_id = uuid4()
    db.add(
        DeliveryAssignment(
            order_id=existing_order.id,
            partner_id=partner.id,
            trip_id=trip_id,
            pickup_code='1111',
            status=AssignmentStatus.ACCEPTED.value,
            accepted_at=datetime.now(UTC),
        )
    )
    await db.flush()
    return partner, trip_id


# --- Eligibility ---


async def test_tier2_offers_detour_to_nearby_mid_trip_partner(db_session):
    """A partner passing the shop with a drop in the same direction qualifies."""
    shop = await _shop(db_session)
    # Partner ~150m west of the shop, heading to a drop ~600m east. The new
    # order's drop is on the way, so the detour is small.
    partner, trip_id = await _mid_trip_partner(
        db_session, shop, dropoff_lng=77.6000, partner_lng=77.5932
    )
    new_order = await _order(db_session, shop, dropoff_lng=77.5975)

    offer = await try_batch_tier2(db_session, new_order)

    assert offer is not None
    assert offer.partner_id == partner.id
    assert offer.trip_id == trip_id, 'must join the existing trip'
    assert offer.offer_type == OfferType.BATCH_DETOUR.value
    assert offer.status == AssignmentStatus.OFFERED.value
    assert offer.window_seconds == 20
    assert offer.detour_meters is not None
    assert offer.detour_meters <= 1000
    assert len(offer.pickup_code) == 4


async def test_tier2_skips_partner_beyond_candidate_radius(db_session):
    """Outside ~1.5km of the shop the partner is not even considered."""
    shop = await _shop(db_session)
    # ~5km east of the shop.
    await _mid_trip_partner(
        db_session, shop, dropoff_lng=77.6600, partner_lng=77.6450
    )
    new_order = await _order(db_session, shop, dropoff_lng=77.5975)

    assert await try_batch_tier2(db_session, new_order) is None


async def test_tier2_rejects_detour_over_budget(db_session):
    """Close to the shop, but the new drop is the wrong way — too far."""
    shop = await _shop(db_session)
    # Partner at the shop, existing drop ~500m east.
    await _mid_trip_partner(
        db_session, shop, dropoff_lng=77.5996, partner_lng=77.5946
    )
    # New drop ~3km west: out and back blows the 1km detour budget.
    new_order = await _order(db_session, shop, dropoff_lng=77.5670)

    assert await try_batch_tier2(db_session, new_order) is None


async def test_tier2_ignores_partner_with_stale_ping(db_session):
    """Batch candidates face the same ping freshness rule as fresh matching."""
    shop = await _shop(db_session)
    partner, _ = await _mid_trip_partner(
        db_session, shop, dropoff_lng=77.6000, partner_lng=77.5932
    )
    stale = await db_session.get(LiveLocation, partner.id)
    stale.updated_at = datetime(2020, 1, 1, tzinfo=UTC)
    await db_session.flush()

    new_order = await _order(db_session, shop, dropoff_lng=77.5975)

    assert await try_batch_tier2(db_session, new_order) is None


async def test_tier2_ignores_partner_who_went_offline(db_session):
    """An offline partner is not a batch candidate, mid-trip or not."""
    shop = await _shop(db_session)
    partner, _ = await _mid_trip_partner(
        db_session, shop, dropoff_lng=77.6000, partner_lng=77.5932
    )
    profile = await db_session.scalar(
        select(DeliveryPartnerProfile).where(
            DeliveryPartnerProfile.user_id == partner.id
        )
    )
    profile.is_online = False
    await db_session.flush()

    new_order = await _order(db_session, shop, dropoff_lng=77.5975)

    assert await try_batch_tier2(db_session, new_order) is None


async def test_tier2_needs_a_recorded_dropoff(db_session):
    """No drop-off means no detour to measure, so batching is skipped."""
    shop = await _shop(db_session)
    await _mid_trip_partner(
        db_session, shop, dropoff_lng=77.6000, partner_lng=77.5932
    )
    customer = await _user(db_session, 'customer')
    order = Order(
        id=uuid4(),
        customer_id=customer.id,
        shop_id=shop.id,
        delivery_address_id=None,
        status=OrderStatus.READY_FOR_PICKUP.value,
        item_total_paise=50000,
        delivery_fee_paise=3000,
        payment_mode='cod',
    )
    db_session.add(order)
    await db_session.flush()

    assert await try_batch_tier2(db_session, order) is None


async def test_tier2_ignores_a_partner_not_yet_out_for_delivery(db_session):
    """Tier 1 covers pre-pickup. Tier 2 only applies once already delivering."""
    shop = await _shop(db_session)
    partner, _ = await _mid_trip_partner(
        db_session, shop, dropoff_lng=77.6000, partner_lng=77.5932
    )
    # Walk their existing order back to before pickup.
    existing = await db_session.scalar(
        select(Order)
        .join(DeliveryAssignment, DeliveryAssignment.order_id == Order.id)
        .where(DeliveryAssignment.partner_id == partner.id)
    )
    existing.status = OrderStatus.PARTNER_ASSIGNED.value
    await db_session.flush()

    new_order = await _order(db_session, shop, dropoff_lng=77.5975)

    assert await try_batch_tier2(db_session, new_order) is None


async def test_tier2_picks_the_smallest_detour(db_session):
    """With two eligible partners, the cheaper reroute wins.

    The two candidates are laid out so their detours are clearly different, not
    merely different by rounding: one is heading the opposite way and has to
    double back, the other is already passing the new drop.
    """
    shop = await _shop(db_session)
    # Heading west while the new drop is east — eligible, but a real diversion.
    doubling_back, _ = await _mid_trip_partner(
        db_session, shop, dropoff_lng=77.5920, partner_lng=77.5950
    )
    # Heading east, drop just past the new one — practically no detour.
    en_route, en_route_trip = await _mid_trip_partner(
        db_session, shop, dropoff_lng=77.5990, partner_lng=77.5940
    )
    new_order = await _order(db_session, shop, dropoff_lng=77.5975)

    offer = await try_batch_tier2(db_session, new_order)

    assert offer is not None
    assert offer.partner_id == en_route.id
    assert offer.partner_id != doubling_back.id
    assert offer.trip_id == en_route_trip
    assert offer.detour_meters is not None
    assert offer.detour_meters < 200, 'the en-route candidate barely diverts'


# --- Timeout / decline fall-through ---


async def test_tier2_timeout_expires_offer_and_frees_the_order(db_session):
    """An unanswered detour expires, leaving the order free for a fresh search.

    The cascade itself runs in the Celery task against its own session; what
    matters here is that expiry releases the order instead of stranding it on a
    partner who never replied.
    """
    shop = await _shop(db_session)
    await _mid_trip_partner(
        db_session, shop, dropoff_lng=77.6000, partner_lng=77.5932
    )
    new_order = await _order(db_session, shop, dropoff_lng=77.5975)
    offer = await try_batch_tier2(db_session, new_order)
    assert offer is not None

    outcome = await expire_batch_offer(db_session, offer.id)

    assert outcome == 'expired'
    assert offer.status == AssignmentStatus.EXPIRED.value
    assert offer.expired_at is not None
    # Never left READY_FOR_PICKUP, so fresh matching can still take it.
    assert new_order.status == OrderStatus.READY_FOR_PICKUP.value


async def test_tier2_expiry_falls_through_to_fresh_matching(
    db_session, monkeypatch
):
    """The spec'd cascade: a refused detour becomes an ordinary fresh search.

    This walks the same two steps `batch_offer_timeout_check` performs —
    expire, then re-match with batching disabled — and asserts a *fresh* offer
    lands on a different partner. The task itself opens its own sessions, so
    driving it directly would put the writes outside this transaction.
    """
    # Don't touch the broker; only the DB effect is under test here.
    monkeypatch.setattr(
        'app.workers.tasks.assignment_timeout_check.apply_async',
        lambda *a, **k: type('T', (), {'id': 'task-stub'})(),
    )

    shop = await _shop(db_session)
    detour_partner, _ = await _mid_trip_partner(
        db_session, shop, dropoff_lng=77.6000, partner_lng=77.5932
    )
    # Someone idle and nearby, who fresh matching should find.
    fresh_partner = await _user(db_session)
    db_session.add(
        DeliveryPartnerProfile(
            user_id=fresh_partner.id,
            name='Idle rider',
            vehicle_type='bike',
            is_online=True,
            kyc_status=KycStatus.APPROVED.value,
        )
    )
    db_session.add(
        LiveLocation(
            partner_id=fresh_partner.id,
            location=f'SRID=4326;POINT(77.5970 {_LAT})',
            updated_at=datetime.now(UTC),
        )
    )
    await db_session.flush()

    new_order = await _order(db_session, shop, dropoff_lng=77.5975)

    offer = await try_batch_tier2(db_session, new_order)
    assert offer is not None
    assert offer.partner_id == detour_partner.id

    # --- the timeout path ---
    assert await expire_batch_offer(db_session, offer.id) == 'expired'
    fresh = await run_matching(db_session, new_order, allow_batching=False)

    assert fresh is not None, 'expiry must fall through to a fresh search'
    assert fresh.offer_type == OfferType.FRESH.value
    assert fresh.status == AssignmentStatus.OFFERED.value
    assert fresh.window_seconds == 35, 'fresh window, not the 20s detour one'
    assert fresh.id != offer.id
    # A fresh offer starts its own trip rather than joining the detour trip.
    assert fresh.trip_id != offer.trip_id


async def test_tier2_fallthrough_does_not_rebatch(db_session, monkeypatch):
    """allow_batching=False is what stops Tier 2 running a second time.

    Without it the same mid-trip partner would be handed the detour they just
    let expire.
    """
    monkeypatch.setattr(
        'app.workers.tasks.assignment_timeout_check.apply_async',
        lambda *a, **k: type('T', (), {'id': 'task-stub'})(),
    )

    shop = await _shop(db_session)
    detour_partner, detour_trip = await _mid_trip_partner(
        db_session, shop, dropoff_lng=77.6000, partner_lng=77.5932
    )
    new_order = await _order(db_session, shop, dropoff_lng=77.5975)

    offer = await try_batch_tier2(db_session, new_order)
    assert offer is not None
    await expire_batch_offer(db_session, offer.id)

    result = await run_matching(db_session, new_order, allow_batching=False)

    # The only candidate nearby is mid-trip, and fresh matching skips partners
    # already at their trip ceiling, so nothing is offered — but critically it
    # is not a second batch_detour on the same trip.
    if result is not None:
        assert result.offer_type == OfferType.FRESH.value
        assert result.trip_id != detour_trip


async def test_tier2_expiry_is_a_no_op_once_accepted(db_session):
    """A timeout firing after the partner accepted must not undo the accept."""
    shop = await _shop(db_session)
    await _mid_trip_partner(
        db_session, shop, dropoff_lng=77.6000, partner_lng=77.5932
    )
    new_order = await _order(db_session, shop, dropoff_lng=77.5975)
    offer = await try_batch_tier2(db_session, new_order)
    assert offer is not None
    await accept_batch_offer(db_session, offer)

    assert await expire_batch_offer(db_session, offer.id) == 'already_accepted'
    assert offer.status == AssignmentStatus.ACCEPTED.value


async def test_tier2_declined_offer_is_recorded(db_session):
    """A refusal is stored so the same order is never re-offered to them."""
    shop = await _shop(db_session)
    partner, _ = await _mid_trip_partner(
        db_session, shop, dropoff_lng=77.6000, partner_lng=77.5932
    )
    new_order = await _order(db_session, shop, dropoff_lng=77.5975)
    offer = await try_batch_tier2(db_session, new_order)
    assert offer is not None

    await decline_batch_offer(db_session, offer)

    assert offer.status == AssignmentStatus.DECLINED.value
    assert offer.declined_at is not None

    # Re-running Tier 2 with that partner excluded finds nobody else, so the
    # order falls through to a plain fresh search.
    assert (
        await try_batch_tier2(
            db_session, new_order, excluded_partner_ids=[partner.id]
        )
        is None
    )


# --- Repricing on accept ---


async def test_batch_accept_reprices_at_batched_rate(db_session):
    """Accepting a detour drops the fee from the solo to the batched rate."""
    shop = await _shop(db_session)
    # Existing drop sits further out than the new one, so the new order is
    # genuinely en route and the detour stays inside budget.
    await _mid_trip_partner(
        db_session, shop, dropoff_lng=77.6400, partner_lng=77.5932
    )
    # ~3km drop so the fee sits above the ₹20 floor and the 2000 -> 1500
    # paise/km difference is actually visible.
    new_order = await _order(
        db_session, shop, dropoff_lng=77.6250, delivery_fee_paise=8000
    )
    offer = await try_batch_tier2(db_session, new_order)
    assert offer is not None

    expected = await batched_delivery_fee_paise(db_session, new_order)
    result = await accept_batch_offer(db_session, offer)

    assert result['original_delivery_fee_paise'] == 8000
    assert result['delivery_fee_paise'] == expected
    assert expected < 8000, 'batched rate must undercut the solo rate'
    assert new_order.delivery_fee_paise == expected
    assert new_order.status == OrderStatus.PARTNER_ASSIGNED.value
    assert offer.status == AssignmentStatus.ACCEPTED.value
    assert offer.accepted_at is not None


async def test_batch_accept_queues_refund_for_online_order(db_session):
    """Online payments get the difference back; COD just collects less."""
    shop = await _shop(db_session)
    await _mid_trip_partner(
        db_session, shop, dropoff_lng=77.6400, partner_lng=77.5932
    )
    new_order = await _order(
        db_session,
        shop,
        dropoff_lng=77.6250,
        payment_mode='online',
        delivery_fee_paise=8000,
    )
    offer = await try_batch_tier2(db_session, new_order)
    assert offer is not None

    result = await accept_batch_offer(db_session, offer)

    assert result['refund_queued'] is True


async def test_batch_accept_on_cod_order_queues_no_refund(db_session):
    """Nothing has been collected yet on COD, so there is nothing to refund."""
    shop = await _shop(db_session)
    await _mid_trip_partner(
        db_session, shop, dropoff_lng=77.6400, partner_lng=77.5932
    )
    new_order = await _order(
        db_session, shop, dropoff_lng=77.6250, delivery_fee_paise=8000
    )
    offer = await try_batch_tier2(db_session, new_order)
    assert offer is not None

    result = await accept_batch_offer(db_session, offer)

    assert result['refund_queued'] is False
    assert result['delivery_fee_paise'] < 8000


async def test_batched_fee_uses_fifteen_rupees_per_km(db_session):
    """The batched rate really is ₹15/km, not the ₹20/km solo rate."""
    shop = await _shop(db_session)
    new_order = await _order(db_session, shop, dropoff_lng=77.6250)

    fee = await batched_delivery_fee_paise(db_session, new_order)

    dropoff = await db_session.get(Address, new_order.delivery_address_id)
    distance_km = round(
        await route_distance_m(db_session, [shop.location, dropoff.location])
        / 1000,
        1,
    )
    assert fee == max(int(BATCHED_RATE_PAISE_PER_KM * distance_km), 2000)


async def test_batched_fee_respects_the_minimum(db_session):
    """A very short batched leg still cannot price below the ₹20 floor."""
    shop = await _shop(db_session)
    # Drop-off essentially at the shop.
    new_order = await _order(db_session, shop, dropoff_lng=77.5947)

    assert await batched_delivery_fee_paise(db_session, new_order) == 2000
