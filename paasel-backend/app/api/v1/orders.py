"""Orders router — order lifecycle endpoints."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Body
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import DbSession, require_role
from app.core.errors import AppError
from app.domain.enums import AssignmentStatus, OfferType, OrderStatus, UserRole
from app.models.entities import (
    DeliveryAssignment,
    LiveLocation,
    Order,
    OrderItem,
    OrderPhoto,
    Shop,
    User,
)
from app.services.batch_offers import (
    accept_batch_offer,
    decline_batch_offer,
    revoke_timeout,
)
from app.services.missing_item import handle_customer_decision, mark_item_unavailable
from app.services.order_state_machine import transition
from app.services.partner_matching import run_matching
from app.workers.tasks import customer_decision_timeout

router = APIRouter(prefix="/api/v1/orders", tags=["orders"])


class CustomerDecisionBody(BaseModel):
    decision: str  # proceed | hold | cancel


class ConfirmPickupBody(BaseModel):
    pickup_code: str


class ConfirmDeliveryBody(BaseModel):
    otp: str


class MarkUnavailableBody(BaseModel):
    reason: str


# --- Role-check (hidden) ---
@router.get("/_role-check", include_in_schema=False)
async def role_check(
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
) -> dict[str, str]:
    return {"status": "authorized", "role": user.role}


# --- Shop endpoints ---


@router.post("/{order_id}/accept")
async def accept_order(
    order_id: UUID,
    user: Annotated[User, require_role(UserRole.SHOP_OWNER)],
    db: DbSession,
) -> dict:
    order = await _get_order(db, order_id)
    await _assert_shop_owns_order(db, order, user)
    order = await transition(db, order, OrderStatus.ACCEPTED_BY_SHOP)
    order = await transition(db, order, OrderStatus.PREPARING)
    await db.commit()
    return {"status": order.status}


@router.post("/{order_id}/reject")
async def reject_order(
    order_id: UUID,
    user: Annotated[User, require_role(UserRole.SHOP_OWNER)],
    db: DbSession,
) -> dict:
    order = await _get_order(db, order_id)
    await _assert_shop_owns_order(db, order, user)
    order = await transition(db, order, OrderStatus.REJECTED_BY_SHOP)
    await db.commit()
    return {"status": order.status}


@router.post("/{order_id}/items/{item_id}/mark-unavailable")
async def mark_item_unavailable_endpoint(
    order_id: UUID,
    item_id: UUID,
    user: Annotated[User, require_role(UserRole.SHOP_OWNER)],
    db: DbSession,
    body: MarkUnavailableBody = Body(...),
) -> dict:
    order = await _get_order(db, order_id)
    await _assert_shop_owns_order(db, order, user)
    order = await mark_item_unavailable(db, order, item_id, body.reason)
    # Schedule 7-minute timeout
    customer_decision_timeout.apply_async(
        args=[str(order.id)], countdown=420
    )
    await db.commit()
    return {"status": order.status}


@router.post("/{order_id}/packing-photo")
async def upload_packing_photo(
    order_id: UUID,
    user: Annotated[User, require_role(UserRole.SHOP_OWNER)],
    db: DbSession,
    photo_url: str = Body(..., embed=True),
) -> dict:
    order = await _get_order(db, order_id)
    await _assert_shop_owns_order(db, order, user)
    db.add(OrderPhoto(
        order_id=order.id,
        captured_by="shop",
        stage="packing",
        photo_url=photo_url,
    ))
    await db.commit()
    return {"status": "uploaded"}


@router.post("/{order_id}/mark-ready")
async def mark_ready(
    order_id: UUID,
    user: Annotated[User, require_role(UserRole.SHOP_OWNER)],
    db: DbSession,
) -> dict:
    order = await _get_order(db, order_id)
    await _assert_shop_owns_order(db, order, user)
    order = await transition(db, order, OrderStatus.READY_FOR_PICKUP)
    # Trigger matching
    assignment = await run_matching(db, order)
    if assignment:
        order = await transition(db, order, OrderStatus.PARTNER_ASSIGNED)
    await db.commit()
    return {"status": order.status, "assignment_id": str(assignment.id) if assignment else None}


# --- Customer endpoints ---


@router.post("/{order_id}/customer-decision")
async def customer_decision(
    order_id: UUID,
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
    body: CustomerDecisionBody = Body(...),
) -> dict:
    order = await _get_order(db, order_id)
    if order.customer_id != user.id:
        raise AppError(403, "forbidden", "Not your order")
    order = await handle_customer_decision(db, order, body.decision)
    await db.commit()
    return {"status": order.status}


@router.get("/{order_id}/tracking")
async def get_tracking(
    order_id: UUID,
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
) -> dict:
    order = await _get_order(db, order_id)
    if order.customer_id != user.id:
        raise AppError(403, "forbidden", "Not your order")

    response: dict = {"order_id": str(order.id), "status": order.status}

    # Include live location if partner is assigned through delivery
    trackable_states = {
        OrderStatus.PARTNER_ASSIGNED.value,
        OrderStatus.PARTNER_ARRIVED_AT_SHOP.value,
        OrderStatus.PICKED_UP.value,
        OrderStatus.OUT_FOR_DELIVERY.value,
    }
    if order.status in trackable_states:
        assignment = await db.scalar(
            select(DeliveryAssignment)
            .where(DeliveryAssignment.order_id == order.id)
            .order_by(DeliveryAssignment.assigned_at.desc())
        )
        if assignment:
            live = await db.get(LiveLocation, assignment.partner_id)
            if live:
                response["partner_location"] = {
                    "partner_id": str(assignment.partner_id),
                    "updated_at": live.updated_at.isoformat() if live.updated_at else None,
                }

    return response


# --- Delivery partner endpoints ---


@router.post("/{order_id}/pickup-photo")
async def upload_pickup_photo(
    order_id: UUID,
    user: Annotated[User, require_role(UserRole.DELIVERY_PARTNER)],
    db: DbSession,
    photo_url: str = Body(..., embed=True),
) -> dict:
    order = await _get_order(db, order_id)
    db.add(OrderPhoto(
        order_id=order.id,
        captured_by="delivery_partner",
        stage="pickup",
        photo_url=photo_url,
    ))
    await db.commit()
    return {"status": "uploaded"}


@router.post("/{order_id}/confirm-pickup")
async def confirm_pickup(
    order_id: UUID,
    user: Annotated[User, require_role(UserRole.DELIVERY_PARTNER)],
    db: DbSession,
    body: ConfirmPickupBody = Body(...),
) -> dict:
    order = await _get_order(db, order_id)
    order = await transition(
        db, order, OrderStatus.PICKED_UP, pickup_code=body.pickup_code
    )
    await db.commit()
    return {"status": order.status}


@router.post("/{order_id}/delivery-photo")
async def upload_delivery_photo(
    order_id: UUID,
    user: Annotated[User, require_role(UserRole.DELIVERY_PARTNER)],
    db: DbSession,
    photo_url: str = Body(..., embed=True),
) -> dict:
    order = await _get_order(db, order_id)
    db.add(OrderPhoto(
        order_id=order.id,
        captured_by="delivery_partner",
        stage="delivery",
        photo_url=photo_url,
    ))
    await db.commit()
    return {"status": "uploaded"}


@router.post("/{order_id}/confirm-delivery")
async def confirm_delivery(
    order_id: UUID,
    user: Annotated[User, require_role(UserRole.DELIVERY_PARTNER)],
    db: DbSession,
    body: ConfirmDeliveryBody = Body(...),
) -> dict:
    order = await _get_order(db, order_id)
    order = await transition(db, order, OrderStatus.DELIVERED, otp=body.otp)
    order = await transition(db, order, OrderStatus.COMPLETED)
    await db.commit()
    return {"status": order.status}


# --- Assignment endpoints (delivery partner) ---


@router.post("/assignments/{assignment_id}/accept")
async def accept_assignment(
    assignment_id: UUID,
    user: Annotated[User, require_role(UserRole.DELIVERY_PARTNER)],
    db: DbSession,
) -> dict:
    from datetime import UTC, datetime

    assignment = await db.get(DeliveryAssignment, assignment_id)
    if not assignment:
        raise AppError(404, "not_found", "Assignment not found")
    if assignment.partner_id != user.id:
        raise AppError(403, "forbidden", "Not your assignment")
    if assignment.accepted_at is not None:
        raise AppError(409, "already_accepted", "Already accepted")
    if assignment.status != AssignmentStatus.OFFERED.value:
        raise AppError(
            409,
            "offer_closed",
            "This offer has expired — it went to another partner",
        )

    # Both of these, not just accepted_at. Everything else keys off status:
    # outstanding_offer would keep serving this as unanswered, and
    # active_accepted_assignment would not see it — which quietly lets a partner
    # go offline in the middle of a delivery, the exact case the 409 exists for.
    assignment.status = AssignmentStatus.ACCEPTED.value
    assignment.accepted_at = datetime.now(UTC)
    revoke_timeout(assignment)

    # Transition order to PARTNER_ASSIGNED if still READY_FOR_PICKUP
    order = await db.get(Order, assignment.order_id)
    if order and order.status == OrderStatus.READY_FOR_PICKUP.value:
        await transition(db, order, OrderStatus.PARTNER_ASSIGNED)

    await db.commit()
    return {"status": "accepted", "order_id": str(assignment.order_id)}


@router.post("/assignments/{assignment_id}/batch-accept")
async def batch_accept_assignment(
    assignment_id: UUID,
    user: Annotated[User, require_role(UserRole.DELIVERY_PARTNER)],
    db: DbSession,
) -> dict:
    """Accept a Tier 2 mid-trip detour offer, before its 20s window closes."""
    assignment = await _get_assignment(db, assignment_id, user)
    result = await accept_batch_offer(db, assignment)
    await db.commit()
    return result


@router.post("/assignments/{assignment_id}/batch-decline")
async def batch_decline_assignment(
    assignment_id: UUID,
    user: Annotated[User, require_role(UserRole.DELIVERY_PARTNER)],
    db: DbSession,
) -> dict:
    """Refuse a Tier 2 detour.

    The order then goes through a normal fresh search, and is never re-offered
    to this partner.
    """
    assignment = await _get_assignment(db, assignment_id, user)
    if assignment.offer_type != OfferType.BATCH_DETOUR.value:
        raise AppError(
            422, "not_a_batch_offer", "This assignment is not a detour offer"
        )
    if assignment.status != AssignmentStatus.OFFERED.value:
        raise AppError(409, "offer_closed", "This offer is no longer open")

    order_id = assignment.order_id
    await decline_batch_offer(db, assignment)
    await db.commit()

    order = await db.get(Order, order_id)
    if order:
        await run_matching(db, order, allow_batching=False)

    return {"status": "declined"}


@router.post("/assignments/{assignment_id}/decline")
async def decline_assignment(
    assignment_id: UUID,
    user: Annotated[User, require_role(UserRole.DELIVERY_PARTNER)],
    db: DbSession,
) -> dict:
    assignment = await db.get(DeliveryAssignment, assignment_id)
    if not assignment:
        raise AppError(404, "not_found", "Assignment not found")
    if assignment.partner_id != user.id:
        raise AppError(403, "forbidden", "Not your assignment")
    if assignment.accepted_at is not None:
        raise AppError(409, "already_accepted", "Cannot decline an accepted assignment")

    # Remove the declined assignment
    await db.delete(assignment)
    await db.commit()

    # The timeout task will handle re-matching when it fires
    return {"status": "declined"}


# --- Helpers ---


async def _get_order(db: AsyncSession, order_id: UUID) -> Order:
    order = await db.get(Order, order_id)
    if not order:
        raise AppError(404, "not_found", "Order not found")
    return order


async def _get_assignment(
    db: AsyncSession, assignment_id: UUID, user: User
) -> DeliveryAssignment:
    assignment = await db.get(DeliveryAssignment, assignment_id)
    if not assignment:
        raise AppError(404, "not_found", "Assignment not found")
    if assignment.partner_id != user.id:
        raise AppError(403, "forbidden", "Not your assignment")
    return assignment


async def _assert_shop_owns_order(
    db: AsyncSession, order: Order, user: User
) -> None:
    """Refuse an order that belongs to somebody else's shop.

    This used to be an empty body with a note about doing it properly later,
    which made every shop endpoint on this router effectively unauthenticated
    past the role check: any signed-in shop owner could accept, reject, mark
    items unavailable on, or hand off an order belonging to any other shop in
    the system. The role gate only proves *a* shop owner is calling.

    shops.owner_id is unique, so one lookup settles it.
    """
    owner_id = await db.scalar(
        select(Shop.owner_id).where(Shop.id == order.shop_id)
    )
    if owner_id != user.id:
        raise AppError(403, "forbidden", "Not your shop's order")
    # For now, we trust the shop_owner role + will add ownership validation in Phase 4.
    pass
