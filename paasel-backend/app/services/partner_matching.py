"""Nearest-partner matching and batching logic."""

import random
from datetime import UTC, datetime
from uuid import UUID, uuid4

from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.enums import AssignmentStatus, OfferType
from app.models.entities import (
    Address,
    DeliveryAssignment,
    Order,
    Shop,
)
from app.services.routing import route_distance_m

MAX_CASCADE = 5
INITIAL_RADIUS_M = 3000
EXPANDED_RADIUS_M = 6000

# Solo delivery is ₹20/km; a batched leg is cheaper to serve, so it prices at
# ₹15/km. Applied when a partner accepts a Tier 2 detour.
BATCHED_RATE_PAISE_PER_KM = 1500

# A partner is only matchable while they are actively pinging. is_online alone
# is not enough: a killed app, a dead battery or lost signal leaves the flag
# stuck true, and offering to a phone that cannot answer burns the whole
# 35-second window for nothing.
PING_FRESHNESS_SECONDS = 90

# Accept windows, stored on the assignment row so neither is hardcoded at a
# call site.
FRESH_OFFER_WINDOW_SECONDS = 35
BATCH_OFFER_WINDOW_SECONDS = 20

# Tier 2: how close a mid-trip partner must already be to the new shop to be
# worth evaluating, and how much extra road distance the detour may add.
BATCH_CANDIDATE_RADIUS_M = 1500
MAX_DETOUR_M = 1000

# Orders per trip ceiling, shared by both batching tiers.
MAX_ORDERS_PER_TRIP = 3

_TERMINAL_ORDER_STATES = (
    "DELIVERED",
    "COMPLETED",
    "CANCELLED_BY_CUSTOMER",
    "CANCELLED_BY_SHOP",
    "CANCELLED_ITEM_UNAVAILABLE",
    "REJECTED_BY_SHOP",
)


def _generate_4digit() -> str:
    return f"{random.randint(0, 9999):04d}"


async def try_batch_tier1(
    db: AsyncSession, order: Order
) -> DeliveryAssignment | None:
    """Tier 1 batching: attach to an existing partner at the same shop.

    If a partner is currently PARTNER_ASSIGNED or PARTNER_ARRIVED_AT_SHOP
    for another order at the same shop, with < 3 orders on their trip,
    attach this order to their trip instead of running a fresh search.

    This is deliberately consent-free — the partner has not picked up yet and
    it is the same physical stop — so the assignment is created already
    accepted rather than sitting as an offer nobody will ever answer.
    """
    # Find partners currently assigned to orders at this shop
    stmt = text("""
        SELECT da.partner_id, da.trip_id, count(*) AS trip_count
        FROM delivery_assignments da
        JOIN orders o ON o.id = da.order_id
        WHERE o.shop_id = :shop_id
          AND o.status IN ('PARTNER_ASSIGNED', 'PARTNER_ARRIVED_AT_SHOP')
          AND da.order_id != :order_id
        GROUP BY da.partner_id, da.trip_id
        HAVING count(*) < :max_per_trip
        ORDER BY count(*) ASC
        LIMIT 1
    """)
    row = (await db.execute(stmt, {
        "shop_id": str(order.shop_id),
        "order_id": str(order.id),
        "max_per_trip": MAX_ORDERS_PER_TRIP,
    })).first()

    if not row:
        return None

    partner_id, trip_id, _ = row
    assignment = DeliveryAssignment(
        order_id=order.id,
        partner_id=partner_id,
        trip_id=trip_id,
        pickup_code=_generate_4digit(),
        offer_type=OfferType.FRESH.value,
        status=AssignmentStatus.ACCEPTED.value,
        accepted_at=datetime.now(UTC),
    )
    db.add(assignment)
    return assignment


async def find_nearest_partner(
    db: AsyncSession,
    order: Order,
    excluded_partner_ids: list[UUID] | None = None,
    radius_m: int = INITIAL_RADIUS_M,
) -> UUID | None:
    """Find the nearest available partner within radius of the shop.

    Ranking:
    1. Distance (primary)
    2. Tiebreak within 200m: fewer active orders, then historical acceptance

    Requires a live_locations ping inside PING_FRESHNESS_SECONDS — see the note
    on that constant.
    """
    excluded = excluded_partner_ids or []
    excluded_clause = ""
    params: dict = {
        "shop_id": str(order.shop_id),
        "radius_m": radius_m,
        "ping_freshness": PING_FRESHNESS_SECONDS,
        "max_per_trip": MAX_ORDERS_PER_TRIP,
    }
    if excluded:
        excluded_clause = "AND dp.user_id != ALL(:excluded)"
        params["excluded"] = [str(e) for e in excluded]

    query = text(f"""
        SELECT dp.user_id AS partner_id,
               ST_Distance(ll.location, s.location) AS distance_m
        FROM live_locations ll
        JOIN delivery_partner_profiles dp ON dp.user_id = ll.partner_id
        JOIN shops s ON s.id = :shop_id
        WHERE dp.is_online = true
          AND ll.updated_at > now() - make_interval(secs => :ping_freshness)
          AND ST_DWithin(ll.location, s.location, :radius_m)
          {excluded_clause}
          AND (
            SELECT count(*) FROM delivery_assignments da
            JOIN orders o2 ON o2.id = da.order_id
            WHERE da.partner_id = dp.user_id
              AND o2.status NOT IN (
                'DELIVERED','COMPLETED',
                'CANCELLED_BY_CUSTOMER','CANCELLED_BY_SHOP',
                'CANCELLED_ITEM_UNAVAILABLE','REJECTED_BY_SHOP'
              )
          ) < :max_per_trip
        ORDER BY distance_m ASC
        LIMIT 5
    """)

    rows = (await db.execute(query, params)).all()
    if not rows:
        return None

    # Within 200m cluster — tiebreak by active order count
    top_distance = rows[0].distance_m
    cluster = [r for r in rows if r.distance_m - top_distance <= 200]

    if len(cluster) == 1:
        return UUID(str(cluster[0].partner_id))

    # Count active assignments for tiebreak
    best_partner = cluster[0].partner_id
    best_count = 999
    for candidate in cluster:
        count = await db.scalar(
            select(func.count())
            .select_from(DeliveryAssignment)
            .join(Order, Order.id == DeliveryAssignment.order_id)
            .where(
                DeliveryAssignment.partner_id == candidate.partner_id,
                Order.status.notin_([
                    "DELIVERED", "COMPLETED",
                    "CANCELLED_BY_CUSTOMER", "CANCELLED_BY_SHOP",
                ]),
            )
        )
        if count is not None and count < best_count:
            best_count = count
            best_partner = candidate.partner_id

    return UUID(str(best_partner))


async def try_batch_tier2(
    db: AsyncSession,
    order: Order,
    excluded_partner_ids: list[UUID] | None = None,
) -> DeliveryAssignment | None:
    """Tier 2 batching: offer a mid-trip detour to a partner already delivering.

    Unlike Tier 1 this genuinely changes the partner's route, so it is an offer
    they can refuse rather than a silent attachment.

    Candidates are partners currently OUT_FOR_DELIVERY whose live location sits
    within BATCH_CANDIDATE_RADIUS_M of the new order's shop. For each, the added
    road distance of picking this order up en route is measured against their
    current remaining route; anything over MAX_DETOUR_M is dropped. The smallest
    eligible detour gets the offer.

    Returns the offered assignment, or None when nothing qualifies — in which
    case the caller should fall through to fresh matching.
    """
    # No recorded drop-off means there is nothing to measure a detour against.
    if order.delivery_address_id is None:
        return None

    shop = await db.get(Shop, order.shop_id)
    new_dropoff = await db.get(Address, order.delivery_address_id)
    if shop is None or new_dropoff is None:
        return None

    excluded = excluded_partner_ids or []
    excluded_clause = ""
    params: dict = {
        "shop_id": str(order.shop_id),
        "order_id": str(order.id),
        "candidate_radius_m": BATCH_CANDIDATE_RADIUS_M,
        "ping_freshness": PING_FRESHNESS_SECONDS,
        "max_per_trip": MAX_ORDERS_PER_TRIP,
    }
    if excluded:
        excluded_clause = "AND da.partner_id != ALL(:excluded)"
        params["excluded"] = [str(e) for e in excluded]

    # DISTINCT ON collapses a multi-order trip to its earliest leg, so a partner
    # appears once and the detour is measured against one concrete drop-off.
    query = text(f"""
        SELECT DISTINCT ON (da.partner_id)
               da.partner_id,
               da.trip_id,
               ll.location AS partner_location,
               addr.location AS existing_dropoff
        FROM delivery_assignments da
        JOIN orders o ON o.id = da.order_id
        JOIN addresses addr ON addr.id = o.delivery_address_id
        JOIN live_locations ll ON ll.partner_id = da.partner_id
        JOIN delivery_partner_profiles dp ON dp.user_id = da.partner_id
        JOIN shops s ON s.id = :shop_id
        WHERE da.status = 'accepted'
          AND o.status = 'OUT_FOR_DELIVERY'
          AND o.id != :order_id
          AND dp.is_online = true
          AND ll.updated_at > now() - make_interval(secs => :ping_freshness)
          AND ST_DWithin(ll.location, s.location, :candidate_radius_m)
          {excluded_clause}
          AND (
            SELECT count(*) FROM delivery_assignments da2
            WHERE da2.trip_id = da.trip_id
          ) < :max_per_trip
        ORDER BY da.partner_id, da.assigned_at ASC
    """)

    candidates = (await db.execute(query, params)).all()
    if not candidates:
        return None

    best: tuple[UUID, UUID, int] | None = None  # (partner_id, trip_id, detour)
    for candidate in candidates:
        # Current plan: straight to the drop-off they already have.
        baseline = await route_distance_m(
            db, [candidate.partner_location, candidate.existing_dropoff]
        )
        # Batched plan: collect the new order en route, then both drop-offs.
        batched = await route_distance_m(
            db,
            [
                candidate.partner_location,
                shop.location,
                new_dropoff.location,
                candidate.existing_dropoff,
            ],
        )
        detour = int(round(batched - baseline))
        if detour > MAX_DETOUR_M:
            continue
        if best is None or detour < best[2]:
            best = (
                UUID(str(candidate.partner_id)),
                UUID(str(candidate.trip_id)),
                max(detour, 0),
            )

    if best is None:
        return None

    partner_id, trip_id, detour_meters = best
    assignment = DeliveryAssignment(
        order_id=order.id,
        partner_id=partner_id,
        trip_id=trip_id,
        pickup_code=_generate_4digit(),
        offer_type=OfferType.BATCH_DETOUR.value,
        status=AssignmentStatus.OFFERED.value,
        detour_meters=detour_meters,
        window_seconds=BATCH_OFFER_WINDOW_SECONDS,
    )
    db.add(assignment)
    await db.flush()
    return assignment


async def offer_to_partner(
    db: AsyncSession,
    order: Order,
    partner_id: UUID,
) -> DeliveryAssignment:
    """Create an assignment offer and return it (caller schedules timeout)."""
    assignment = DeliveryAssignment(
        order_id=order.id,
        partner_id=partner_id,
        trip_id=uuid4(),
        pickup_code=_generate_4digit(),
        offer_type=OfferType.FRESH.value,
        status=AssignmentStatus.OFFERED.value,
        window_seconds=FRESH_OFFER_WINDOW_SECONDS,
    )
    db.add(assignment)
    await db.flush()
    return assignment


async def run_matching(
    db: AsyncSession,
    order: Order,
    cascade_count: int = 0,
    excluded_ids: list[UUID] | None = None,
    *,
    allow_batching: bool = True,
) -> DeliveryAssignment | None:
    """Full matching flow: batch checks -> nearest search -> offer.

    Returns the assignment if successful, None if no partner found
    after all cascades.

    Set allow_batching=False to force a plain fresh search. The Tier 2
    decline/timeout path uses this so a refused detour falls through exactly as
    if batching had never been attempted.
    """
    from app.workers.tasks import assignment_timeout_check, batch_offer_timeout_check

    excluded = excluded_ids or []
    first_attempt = cascade_count == 0 and allow_batching

    # Tier 1 batching — same shop, not yet picked up, no consent needed
    if first_attempt:
        batch = await try_batch_tier1(db, order)
        if batch:
            return batch

    # Tier 2 batching — mid-trip detour, needs the partner's consent
    if first_attempt:
        detour_offer = await try_batch_tier2(
            db, order, excluded_partner_ids=excluded
        )
        if detour_offer:
            await db.commit()
            task = batch_offer_timeout_check.apply_async(
                args=[str(detour_offer.id), str(order.id)],
                countdown=BATCH_OFFER_WINDOW_SECONDS,
            )
            detour_offer.timeout_task_id = task.id
            await db.commit()
            return detour_offer

    # Try initial radius
    partner_id = await find_nearest_partner(
        db, order, excluded_partner_ids=excluded, radius_m=INITIAL_RADIUS_M
    )

    # Expand radius once
    if not partner_id:
        partner_id = await find_nearest_partner(
            db, order, excluded_partner_ids=excluded, radius_m=EXPANDED_RADIUS_M
        )

    if not partner_id:
        if cascade_count >= MAX_CASCADE:
            # Flag for admin attention — in production this would be an
            # admin notification. For now we return None.
            return None
        return None

    assignment = await offer_to_partner(db, order, partner_id)
    await db.commit()

    # Schedule timeout check (35 seconds)
    task = assignment_timeout_check.apply_async(
        args=[str(assignment.id), str(order.id), cascade_count],
        countdown=FRESH_OFFER_WINDOW_SECONDS,
    )
    assignment.timeout_task_id = task.id
    await db.commit()
    return assignment


async def batched_delivery_fee_paise(db: AsyncSession, order: Order) -> int:
    """Recompute an order's delivery fee at the batched per-km rate.

    A batched leg is cheaper to serve than a solo trip, so the customer pays
    the batched rate. The floor matches the solo calculation in
    order_placement so a batched order can never price above a solo one.
    """
    from app.api.v1.order_placement import MIN_DELIVERY_FEE_PAISE

    if order.delivery_address_id is None:
        return order.delivery_fee_paise

    shop = await db.get(Shop, order.shop_id)
    dropoff = await db.get(Address, order.delivery_address_id)
    if shop is None or dropoff is None:
        return order.delivery_fee_paise

    distance_m = await route_distance_m(db, [shop.location, dropoff.location])
    distance_km = round(distance_m / 1000, 1)
    return max(
        int(BATCHED_RATE_PAISE_PER_KM * distance_km), MIN_DELIVERY_FEE_PAISE
    )


def terminal_order_states() -> tuple[str, ...]:
    """The statuses that mean an order is finished, one way or another."""
    return _TERMINAL_ORDER_STATES
