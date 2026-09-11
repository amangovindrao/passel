"""Tier 2 detour offer lifecycle: accept, decline, expire.

Tier 1 batching is silent — same shop, nothing picked up yet, so the order just
joins the trip. Tier 2 reroutes someone mid-delivery, so it is a real offer with
a real window and three possible endings, all handled here.
"""

from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.domain.enums import AssignmentStatus, OfferType, OrderStatus
from app.models.entities import DeliveryAssignment, Order, Shop
from app.services.notifications import push_to_customer, push_to_shop
from app.services.order_state_machine import transition
from app.services.payment_service import initiate_partial_refund

# How long a partner may go without a location ping before the server stops
# believing they are online. Deliberately far longer than the 90s matching
# freshness window: matching should skip a partner after one missed ping, but
# flipping their own flag off is a heavier call and wants more evidence.
STALE_ONLINE_THRESHOLD_SECONDS = 600

_FEE_REDUCTION_REASON = "Delivery fee reduced — order batched onto a shared trip"


def revoke_timeout(assignment: DeliveryAssignment) -> None:
    """Cancel the scheduled timeout so it cannot expire a settled offer."""
    if not assignment.timeout_task_id:
        return
    from app.worker import celery_app

    try:
        celery_app.control.revoke(assignment.timeout_task_id)
    except Exception:  # noqa: BLE001 — broker being down must not fail the request
        # The timeout task is defensive anyway: it re-reads status and skips a
        # settled offer, so a failed revoke is harmless.
        pass


async def outstanding_offer(
    db: AsyncSession, partner_id: UUID
) -> DeliveryAssignment | None:
    """An offer this partner has neither accepted nor refused yet."""
    return await db.scalar(
        select(DeliveryAssignment)
        .where(
            DeliveryAssignment.partner_id == partner_id,
            DeliveryAssignment.status == AssignmentStatus.OFFERED.value,
        )
        .order_by(DeliveryAssignment.assigned_at.desc())
    )


async def active_accepted_assignment(
    db: AsyncSession, partner_id: UUID
) -> DeliveryAssignment | None:
    """An accepted assignment whose order is still in flight.

    This is what blocks a partner from going offline — abandoning a delivery
    someone is waiting on is not something the app should let happen quietly.
    """
    return await db.scalar(
        select(DeliveryAssignment)
        .join(Order, Order.id == DeliveryAssignment.order_id)
        .where(
            DeliveryAssignment.partner_id == partner_id,
            DeliveryAssignment.status == AssignmentStatus.ACCEPTED.value,
            Order.status.notin_([
                OrderStatus.DELIVERED.value,
                OrderStatus.COMPLETED.value,
                OrderStatus.CANCELLED_BY_CUSTOMER.value,
                OrderStatus.CANCELLED_BY_SHOP.value,
                OrderStatus.CANCELLED_ITEM_UNAVAILABLE.value,
                OrderStatus.REJECTED_BY_SHOP.value,
            ]),
        )
        .order_by(DeliveryAssignment.assigned_at.desc())
    )


async def expire_batch_offer(db: AsyncSession, assignment_id: UUID) -> str:
    """Mark an unanswered detour offer expired.

    Returns one of "expired", "already_accepted", "already_settled",
    "not_found" so the caller can decide whether to cascade.
    """
    assignment = await db.get(DeliveryAssignment, assignment_id)
    if assignment is None:
        return "not_found"
    if assignment.status == AssignmentStatus.ACCEPTED.value:
        return "already_accepted"
    if assignment.status != AssignmentStatus.OFFERED.value:
        return "already_settled"

    assignment.status = AssignmentStatus.EXPIRED.value
    assignment.expired_at = datetime.now(UTC)
    await db.flush()
    return "expired"


async def decline_batch_offer(
    db: AsyncSession, assignment: DeliveryAssignment
) -> None:
    """Partner refused the detour. Recorded, and not offered to them again."""
    assignment.status = AssignmentStatus.DECLINED.value
    assignment.declined_at = datetime.now(UTC)
    revoke_timeout(assignment)
    await db.flush()


async def accept_batch_offer(
    db: AsyncSession, assignment: DeliveryAssignment
) -> dict:
    """Partner took the detour.

    Reprices the order at the batched rate and settles the difference the same
    way a missing-item reduction does: refund an online payment, or simply
    collect less on a COD order.
    """
    from app.services.partner_matching import batched_delivery_fee_paise

    if assignment.offer_type != OfferType.BATCH_DETOUR.value:
        raise AppError(
            422, "not_a_batch_offer", "This assignment is not a detour offer"
        )
    if assignment.status == AssignmentStatus.ACCEPTED.value:
        raise AppError(409, "already_accepted", "Already accepted")
    if assignment.status != AssignmentStatus.OFFERED.value:
        raise AppError(
            409,
            "offer_closed",
            "This offer has expired — it went to another partner",
        )

    order = await db.get(Order, assignment.order_id)
    if order is None:
        raise AppError(404, "not_found", "Order not found")

    assignment.status = AssignmentStatus.ACCEPTED.value
    assignment.accepted_at = datetime.now(UTC)
    revoke_timeout(assignment)

    if order.status == OrderStatus.READY_FOR_PICKUP.value:
        await transition(db, order, OrderStatus.PARTNER_ASSIGNED)

    # --- Reprice at the batched rate ---
    original_fee = order.delivery_fee_paise
    batched_fee = await batched_delivery_fee_paise(db, order)
    refund = None
    if batched_fee < original_fee:
        order.delivery_fee_paise = batched_fee
        refund = await initiate_partial_refund(
            db,
            order,
            original_fee - batched_fee,
            reason=_FEE_REDUCTION_REASON,
        )

    await db.flush()

    shop = await db.get(Shop, order.shop_id)
    if shop is not None:
        await push_to_shop(
            shop.id,
            kind="partner_assigned",
            payload={
                "order_id": str(order.id),
                "partner_id": str(assignment.partner_id),
            },
        )
    await push_to_customer(
        order.customer_id,
        kind="partner_assigned",
        payload={
            "order_id": str(order.id),
            "delivery_fee_paise": order.delivery_fee_paise,
        },
    )

    return {
        "status": "accepted",
        "order_id": str(order.id),
        "original_delivery_fee_paise": original_fee,
        "delivery_fee_paise": order.delivery_fee_paise,
        "refund_queued": refund is not None,
    }
