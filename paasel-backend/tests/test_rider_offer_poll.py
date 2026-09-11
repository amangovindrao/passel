"""GET /delivery-partners/me/offer — the pull side of offer delivery.

Push cannot be the only way a rider learns an offer exists. A phone with no
Firebase project, a rotated device token, or an app launched a second after the
offer was made all produce the same outcome: the assignment row is sitting in
the database and nobody has been told. These tests pin down what the poll
returns, and — the part that actually matters — that the countdown it hands the
client is the time genuinely left rather than the original window.
"""

from datetime import UTC, datetime, timedelta

from sqlalchemy import select

from app.domain.enums import AssignmentStatus, OfferType, OrderStatus
from app.models.entities import DeliveryAssignment
from app.services.partner_matching import (
    BATCH_OFFER_WINDOW_SECONDS,
    FRESH_OFFER_WINDOW_SECONDS,
)
from tests.factories import (
    make_assignment,
    make_order,
    make_order_item,
    make_partner,
    make_shop,
)

OFFER = "/api/v1/delivery-partners/me/offer"


async def _offered(db, *, partner, order, age_seconds: int = 0, **kwargs):
    """An OFFERED assignment whose window opened `age_seconds` ago."""
    kwargs.setdefault("offer_type", OfferType.FRESH.value)
    kwargs.setdefault("window_seconds", FRESH_OFFER_WINDOW_SECONDS)
    return await make_assignment(
        db,
        order,
        partner,
        status=AssignmentStatus.OFFERED.value,
        assigned_at=datetime.now(UTC) - timedelta(seconds=age_seconds),
        **kwargs,
    )


# --- Nothing to report ---


async def test_no_offer_returns_null(api, db_session):
    """The common case, polled every few seconds. Must be cheap and quiet."""
    partner = await make_partner(db_session, lng=77.5990)

    resp = await api.as_user(partner).get(OFFER)

    assert resp.status_code == 200
    assert resp.json() == {"offer": None}


async def test_accepted_assignment_is_not_an_offer(api, db_session):
    """Once accepted it belongs to the active-delivery flow, not the offer card.

    Returning it here would re-open the offer overlay on top of a delivery the
    rider is already running.
    """
    shop = await make_shop(db_session)
    partner = await make_partner(db_session, lng=77.5990)
    order = await make_order(
        db_session, shop=shop, status=OrderStatus.PARTNER_ASSIGNED
    )
    await make_assignment(db_session, order, partner, accepted=True)

    resp = await api.as_user(partner).get(OFFER)

    assert resp.json() == {"offer": None}


async def test_accepting_stops_the_offer_being_served(api, db_session):
    """Through the real accept endpoint, not a factory shortcut.

    Everything downstream keys off assignment.status, so an accept that only
    stamps accepted_at leaves the offer looking unanswered — the card comes
    straight back on the next poll, and the accept behind it 409s.
    """
    shop = await make_shop(db_session)
    partner = await make_partner(db_session, lng=77.5990)
    order = await make_order(
        db_session, shop=shop, status=OrderStatus.READY_FOR_PICKUP
    )
    assignment = await _offered(db_session, partner=partner, order=order)

    accepted = await api.as_user(partner).post(
        f"/api/v1/orders/assignments/{assignment.id}/accept"
    )
    assert accepted.status_code == 200

    resp = await api.as_user(partner).get(OFFER)

    assert resp.json() == {"offer": None}


async def test_accepting_records_the_accepted_status(api, db_session):
    """The status is what active_accepted_assignment and the offline 409 read."""
    shop = await make_shop(db_session)
    partner = await make_partner(db_session, lng=77.5990)
    order = await make_order(
        db_session, shop=shop, status=OrderStatus.READY_FOR_PICKUP
    )
    assignment = await _offered(db_session, partner=partner, order=order)
    # Held separately: expire_all() below expires the identity too, and reading
    # it back off the instance would itself trigger a lazy load.
    assignment_id = assignment.id

    await api.as_user(partner).post(
        f"/api/v1/orders/assignments/{assignment_id}/accept"
    )

    # Read the columns straight out, past any ORM caching.
    db_session.expire_all()
    row = (
        await db_session.execute(
            select(
                DeliveryAssignment.status, DeliveryAssignment.accepted_at
            ).where(DeliveryAssignment.id == assignment_id)
        )
    ).one()

    assert row.status == AssignmentStatus.ACCEPTED.value
    assert row.accepted_at is not None


async def test_another_partners_offer_is_not_visible(api, db_session):
    """Offers are addressed to one partner. Nobody else may see or take one."""
    shop = await make_shop(db_session)
    offeree = await make_partner(db_session, lng=77.5990)
    bystander = await make_partner(db_session, lng=77.5991)
    order = await make_order(
        db_session, shop=shop, status=OrderStatus.READY_FOR_PICKUP
    )
    await _offered(db_session, partner=offeree, order=order)

    resp = await api.as_user(bystander).get(OFFER)

    assert resp.json() == {"offer": None}


# --- A live fresh offer ---


async def test_fresh_offer_carries_what_the_card_renders(api, db_session):
    """Every field the offer card shows comes from this one call."""
    shop = await make_shop(db_session)
    partner = await make_partner(db_session, lng=77.5990)
    order = await make_order(
        db_session,
        shop=shop,
        status=OrderStatus.READY_FOR_PICKUP,
        delivery_fee_paise=3000,
    )
    await make_order_item(db_session, order, shop=shop, qty=2)
    await make_order_item(db_session, order, shop=shop, qty=3)
    assignment = await _offered(db_session, partner=partner, order=order)

    resp = await api.as_user(partner).get(OFFER)

    assert resp.status_code == 200
    offer = resp.json()["offer"]
    assert offer["assignment_id"] == str(assignment.id)
    assert offer["order_id"] == str(order.id)
    assert offer["offer_type"] == OfferType.FRESH.value
    assert offer["shop_name"] == "Test Shop"
    assert offer["delivery_fee_paise"] == 3000
    # Quantities, not line count — five things to carry, not two.
    assert offer["item_count"] == 5
    assert offer["detour_meters"] is None
    # ~480m between the shop at 77.5946 and the rider at 77.5990.
    assert 0 < offer["distance_to_shop_m"] < 1000


async def test_fresh_offer_window_is_the_full_35s_when_brand_new(
    api, db_session
):
    shop = await make_shop(db_session)
    partner = await make_partner(db_session, lng=77.5990)
    order = await make_order(
        db_session, shop=shop, status=OrderStatus.READY_FOR_PICKUP
    )
    await _offered(db_session, partner=partner, order=order)

    resp = await api.as_user(partner).get(OFFER)

    window = resp.json()["offer"]["window_seconds"]
    assert window <= FRESH_OFFER_WINDOW_SECONDS
    assert window >= FRESH_OFFER_WINDOW_SECONDS - 2


# --- The countdown, which is the whole reason this endpoint is careful ---


async def test_window_seconds_counts_down_with_elapsed_time(api, db_session):
    """Polled 30s in, a 35s offer has ~5s left — not 35.

    A client that restarted the ring at the full window would show five seconds
    that do not exist and then fail the accept at the end of them.
    """
    shop = await make_shop(db_session)
    partner = await make_partner(db_session, lng=77.5990)
    order = await make_order(
        db_session, shop=shop, status=OrderStatus.READY_FOR_PICKUP
    )
    await _offered(db_session, partner=partner, order=order, age_seconds=30)

    resp = await api.as_user(partner).get(OFFER)

    remaining = resp.json()["offer"]["window_seconds"]
    assert 1 <= remaining <= 6


async def test_expired_offer_is_reported_as_no_offer(api, db_session):
    """Past its window the row may still be OFFERED — the worker clears it.

    Until then it is not something a rider can act on, so it must not reach
    them; the accept would only 409.
    """
    shop = await make_shop(db_session)
    partner = await make_partner(db_session, lng=77.5990)
    order = await make_order(
        db_session, shop=shop, status=OrderStatus.READY_FOR_PICKUP
    )
    await _offered(db_session, partner=partner, order=order, age_seconds=40)

    resp = await api.as_user(partner).get(OFFER)

    assert resp.json() == {"offer": None}


# --- Tier 2 detour offers ---


async def test_detour_offer_reports_its_type_detour_and_shorter_window(
    api, db_session
):
    """The card needs all three to render a detour rather than a fresh offer."""
    shop = await make_shop(db_session)
    partner = await make_partner(db_session, lng=77.5990)
    order = await make_order(
        db_session,
        shop=shop,
        status=OrderStatus.READY_FOR_PICKUP,
        with_address=True,
    )
    await _offered(
        db_session,
        partner=partner,
        order=order,
        offer_type=OfferType.BATCH_DETOUR.value,
        window_seconds=BATCH_OFFER_WINDOW_SECONDS,
        detour_meters=640,
    )

    resp = await api.as_user(partner).get(OFFER)

    offer = resp.json()["offer"]
    assert offer["offer_type"] == OfferType.BATCH_DETOUR.value
    assert offer["detour_meters"] == 640
    assert offer["window_seconds"] <= BATCH_OFFER_WINDOW_SECONDS


async def test_detour_offer_expires_on_its_own_shorter_window(api, db_session):
    """25s is still alive for a fresh offer and long dead for a detour."""
    shop = await make_shop(db_session)
    partner = await make_partner(db_session, lng=77.5990)
    order = await make_order(
        db_session,
        shop=shop,
        status=OrderStatus.READY_FOR_PICKUP,
        with_address=True,
    )
    await _offered(
        db_session,
        partner=partner,
        order=order,
        age_seconds=25,
        offer_type=OfferType.BATCH_DETOUR.value,
        window_seconds=BATCH_OFFER_WINDOW_SECONDS,
        detour_meters=300,
    )

    resp = await api.as_user(partner).get(OFFER)

    assert resp.json() == {"offer": None}


# --- Riders with no live location ---


async def test_offer_without_a_location_ping_omits_the_distance(
    api, db_session
):
    """Distance is nice to have; its absence must not withhold the offer.

    A partner can hold an offer made moments before their ping went stale, and
    an offer they cannot see is worse than one without a distance on it.
    """
    shop = await make_shop(db_session)
    partner = await make_partner(db_session, lng=None)
    order = await make_order(
        db_session, shop=shop, status=OrderStatus.READY_FOR_PICKUP
    )
    await _offered(db_session, partner=partner, order=order)

    resp = await api.as_user(partner).get(OFFER)

    offer = resp.json()["offer"]
    assert offer is not None
    assert offer["distance_to_shop_m"] is None
