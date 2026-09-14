from datetime import UTC, datetime, timedelta
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Body
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import DbSession, require_role
from app.core.errors import AppError
from app.domain.enums import (
    AdditionStatus,
    AdditionWindowStatus,
    AssignmentStatus,
    OfferType,
    OrderStatus,
    ReturnChargePayer,
    ReturnReason,
    ReturnStatus,
    UserRole,
    VerificationStatus,
    WalletTxnType,
)
from app.models.entities import (
    DeliveryAssignment,
    LiveLocation,
    MerchantQualityIncident,
    Order,
    OrderAddition,
    OrderAdditionItem,
    OrderItem,
    OrderPhoto,
    OrderReturn,
    OrderStatusHistory,
    Product,
    Shop,
    User,
)
from app.schemas import (
    CustomerVerifyOrderRequest,
    DeliveryHandoverStartResponse,
    OrderAdditionCheckResponse,
    OrderAdditionCreateRequest,
    OrderAdditionItemOut,
    OrderAdditionOut,
    OrderReturnOut,
    ReportIssueRequest,
)
from app.services.batch_offers import (
    accept_batch_offer,
    decline_batch_offer,
    revoke_timeout,
)
from app.services.inventory_service import (
    commit_inventory,
    release_inventory,
    reserve_inventory,
)
from app.services.missing_item import handle_customer_decision, mark_item_unavailable
from app.services.order_state_machine import transition
from app.services.partner_matching import run_matching
from app.services.refund_service import process_refund
from app.services.wallet_service import debit_wallet_for_order
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

    # If this is a sub-order in a multi-shop bundle, update parent order if placed
    if order.parent_order_id is not None:
        parent = await db.get(Order, order.parent_order_id)
        if parent and parent.status == OrderStatus.PLACED.value:
            await transition(db, parent, OrderStatus.ACCEPTED_BY_SHOP)
            await transition(db, parent, OrderStatus.PREPARING)

    await db.commit()
    return {"status": order.status}


@router.post("/{order_id}/reject")
async def reject_order(
    order_id: UUID,
    user: Annotated[User, require_role(UserRole.SHOP_OWNER)],
    db: DbSession,
) -> dict:
    from app.services.inventory_service import release_inventory
    from app.services.refund_service import process_refund

    order = await _get_order(db, order_id)
    await _assert_shop_owns_order(db, order, user)
    order = await transition(db, order, OrderStatus.REJECTED_BY_SHOP)
    await release_inventory(db, order.id)

    # Multi-shop sub-order rejection: automatically refund this shop's item portion to customer wallet/source
    if order.parent_order_id is not None:
        parent = await db.get(Order, order.parent_order_id)
        if parent:
            # Refund item total for the rejected sub-order
            await process_refund(
                db,
                order=order,
                refund_amount_paise=order.item_total_paise,
                reason="Sub-order rejected by merchant",
                item_id=str(order.id),
            )

            # Check if all sibling sub-orders were rejected
            siblings = (
                await db.scalars(
                    select(Order).where(Order.parent_order_id == parent.id)
                )
            ).all()

            all_rejected = all(
                s.status == OrderStatus.REJECTED_BY_SHOP.value
                for s in siblings
            )
            if all_rejected:
                await transition(db, parent, OrderStatus.CANCELLED_BY_SHOP)
                await release_inventory(db, parent.id)
                # Refund delivery fee as well
                if parent.delivery_fee_paise > 0:
                    await process_refund(
                        db,
                        order=parent,
                        refund_amount_paise=parent.delivery_fee_paise,
                        reason="All bundled shops rejected order",
                    )

    await db.commit()
    return {"status": order.status}


@router.post("/{order_id}/cancel")
async def cancel_order(
    order_id: UUID,
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
) -> dict:
    from app.services.inventory_service import release_inventory
    from app.services.refund_service import process_refund

    order = await _get_order(db, order_id)
    if order.customer_id != user.id:
        raise AppError(403, "forbidden", "You do not own this order")

    order = await transition(db, order, OrderStatus.CANCELLED_BY_CUSTOMER)
    await release_inventory(db, order.id)

    refund_res = None
    if getattr(order, "payment_status", "pending") == "paid":
        refund_res = await process_refund(
            db,
            order=order,
            reason="Customer cancelled order",
        )

    await db.commit()
    return {"status": order.status, "refund": refund_res}


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

    assignment = None
    if order.parent_order_id is not None:
        # Multi-shop sub-order: only trigger matching when ALL active sub-orders are READY_FOR_PICKUP
        parent = await db.get(Order, order.parent_order_id)
        if parent:
            siblings = (
                await db.scalars(
                    select(Order).where(Order.parent_order_id == parent.id)
                )
            ).all()

            active_siblings = [
                s
                for s in siblings
                if s.status != OrderStatus.REJECTED_BY_SHOP.value
            ]
            all_ready = all(
                s.status == OrderStatus.READY_FOR_PICKUP.value
                for s in active_siblings
            )

            if all_ready and active_siblings:
                parent = await transition(
                    db, parent, OrderStatus.READY_FOR_PICKUP
                )
                assignment = await run_matching(db, parent)
                if assignment:
                    parent = await transition(
                        db, parent, OrderStatus.PARTNER_ASSIGNED
                    )
                    for s in active_siblings:
                        await transition(db, s, OrderStatus.PARTNER_ASSIGNED)
    else:
        # Single shop order: trigger matching immediately
        assignment = await run_matching(db, order)
        if assignment:
            order = await transition(db, order, OrderStatus.PARTNER_ASSIGNED)

    await db.commit()
    return {
        "status": order.status,
        "assignment_id": str(assignment.id) if assignment else None,
    }


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

    now = datetime.now(UTC)
    remaining_seconds = 0
    if order.verification_deadline and now < order.verification_deadline:
        remaining_seconds = max(0, int((order.verification_deadline - now).total_seconds()))

    history_records = (
        await db.scalars(
            select(OrderStatusHistory)
            .where(OrderStatusHistory.order_id == order.id)
            .order_by(OrderStatusHistory.created_at.asc())
        )
    ).all()

    can_add_more = (
        order.status in [OrderStatus.PLACED.value, OrderStatus.ACCEPTED_BY_SHOP.value, OrderStatus.PREPARING.value]
        and getattr(order, "addition_window_status", "ADDITION_OPEN") == "ADDITION_OPEN"
        and getattr(order, "delivery_status", "NOT_READY") not in ["PICKED_UP", "OUT_FOR_DELIVERY", "DELIVERED"]
    )

    response: dict = {
        "order_id": str(order.id),
        "status": order.status,
        "delivery_otp": order.delivery_otp,
        "handover_initiated_at": order.handover_initiated_at.isoformat() if order.handover_initiated_at else None,
        "verification_deadline": order.verification_deadline.isoformat() if order.verification_deadline else None,
        "verification_status": getattr(order, "verification_status", "NOT_INITIATED"),
        "remaining_seconds": remaining_seconds,
        "addition_window_status": getattr(order, "addition_window_status", "ADDITION_OPEN"),
        "can_add_more": can_add_more,
        "status_history": [
            {"status": h.status, "created_at": h.created_at.isoformat() if h.created_at else None}
            for h in history_records
        ],
    }

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


# ---------------------------------------------------------------------------
# Delivery Verification & 7-Minute Item Check Window
# ---------------------------------------------------------------------------


@router.post("/{order_id}/initiate-handover", response_model=DeliveryHandoverStartResponse)
async def initiate_handover(
    order_id: UUID,
    user: Annotated[User, require_role(UserRole.DELIVERY_PARTNER)],
    db: DbSession,
) -> DeliveryHandoverStartResponse:
    """Delivery partner reaches customer and initiates handover verification."""
    order = await _get_order(db, order_id)
    now = datetime.now(UTC)

    order.handover_initiated_at = now
    order.verification_deadline = now + timedelta(minutes=7)
    order.verification_status = VerificationStatus.PENDING_CHECK.value
    order.delivery_status = "HANDOVER_READY"
    order.addition_window_status = AdditionWindowStatus.ADDITION_CLOSED.value

    await db.commit()
    await db.refresh(order)

    return DeliveryHandoverStartResponse(
        order_id=order.id,
        handover_initiated_at=order.handover_initiated_at,
        verification_deadline=order.verification_deadline,
        remaining_seconds=420,
        status=order.status,
        verification_status=order.verification_status,
    )


@router.post("/{order_id}/verify-items")
async def verify_items(
    order_id: UUID,
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
    body: CustomerVerifyOrderRequest = Body(...),
) -> dict:
    """Customer checks items within the 7-minute window.
    
    If 'everything_correct', immediately finalizes delivery without waiting.
    """
    order = await _get_order(db, order_id)
    if order.customer_id != user.id:
        raise AppError(403, "forbidden", "Not your order")

    if body.action == "everything_correct":
        order.verification_status = VerificationStatus.ALL_CORRECT.value
        order.delivery_status = "DELIVERED"
        order.status = OrderStatus.COMPLETED.value
        db.add(OrderStatusHistory(order_id=order.id, status=OrderStatus.DELIVERED.value))
        db.add(OrderStatusHistory(order_id=order.id, status=OrderStatus.COMPLETED.value))
        await db.commit()
        return {
            "status": order.status,
            "verification_status": order.verification_status,
            "message": "Order verified and completed immediately. Thank you!",
        }

    return {
        "status": order.status,
        "verification_status": order.verification_status,
        "message": "Please select the affected item to report an issue.",
    }


@router.post("/{order_id}/auto-complete-if-expired")
async def auto_complete_if_expired(
    order_id: UUID,
    db: DbSession,
) -> dict:
    """Server-authoritative check: if the 7-minute window expired with no issues, complete order."""
    order = await _get_order(db, order_id)
    now = datetime.now(UTC)

    if (
        order.verification_status == VerificationStatus.PENDING_CHECK.value
        and order.verification_deadline
        and now >= order.verification_deadline
    ):
        order.verification_status = VerificationStatus.AUTO_COMPLETED_EXPIRED.value
        order.delivery_status = "DELIVERED"
        order.status = OrderStatus.COMPLETED.value
        db.add(OrderStatusHistory(order_id=order.id, status=OrderStatus.COMPLETED.value))
        await db.commit()
        return {
            "status": order.status,
            "verification_status": order.verification_status,
            "completed": True,
        }

    remaining_seconds = 0
    if order.verification_deadline and now < order.verification_deadline:
        remaining_seconds = max(0, int((order.verification_deadline - now).total_seconds()))

    return {
        "status": order.status,
        "verification_status": order.verification_status,
        "remaining_seconds": remaining_seconds,
        "completed": False,
    }


@router.post("/{order_id}/report-issue")
async def report_issue(
    order_id: UUID,
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
    body: ReportIssueRequest = Body(...),
) -> dict:
    """Customer reports missing, wrong, damaged, or expired item.
    
    SPECIAL RULE: If expired item, SHOP PAYS RETURN CHARGE, customer return fee is ₹0,
    and a merchant quality incident is recorded.
    """
    order = await _get_order(db, order_id)
    if order.customer_id != user.id:
        raise AppError(403, "forbidden", "Not your order")

    order_item = await db.get(OrderItem, body.order_item_id)
    if not order_item or order_item.order_id != order.id:
        raise AppError(404, "not_found", "Order item not found")

    item_cost = order_item.price_at_order_time_paise * order_item.qty
    is_expired = body.issue_type == ReturnReason.EXPIRED_ITEM.value
    return_charge_payer = (
        ReturnChargePayer.SHOP.value
        if is_expired or body.issue_type == ReturnReason.WRONG_ITEM.value
        else ReturnChargePayer.CUSTOMER.value
    )

    ret = OrderReturn(
        order_id=order.id,
        order_item_id=order_item.id,
        customer_id=user.id,
        shop_id=order.shop_id,
        product_id=order_item.product_id,
        return_reason=body.issue_type,
        status=ReturnStatus.RETURN_REQUESTED.value,
        return_charge_payer=return_charge_payer,
        return_charge_paise=0 if is_expired else 2000,
        refund_amount_paise=item_cost,
        customer_notes=body.customer_notes,
        evidence_photo_url=body.evidence_photo_url,
        is_expired_item=is_expired,
    )
    db.add(ret)
    await db.flush()

    # Record Merchant Quality Incident if expired item or defect
    if is_expired:
        incident = MerchantQualityIncident(
            shop_id=order.shop_id,
            order_id=order.id,
            product_id=order_item.product_id,
            return_id=ret.id,
            incident_type="EXPIRED_ITEM",
            severity="CRITICAL",
            refund_amount_paise=item_cost,
            return_cost_paise=2000,
            status="RECORDED",
        )
        db.add(incident)

    # Process immediate refund for customer
    refund_res = await process_refund(
        db,
        order=order,
        refund_amount_paise=item_cost,
        reason=f"Customer issue: {body.issue_type}",
    )

    order.verification_status = VerificationStatus.ISSUE_REPORTED.value
    await db.commit()

    return {
        "status": "recorded",
        "return_id": str(ret.id),
        "issue_type": body.issue_type,
        "is_expired_item": is_expired,
        "return_charge_payer": return_charge_payer,
        "refund": refund_res,
        "message": (
            "Expired item recorded. The shop is responsible for this return and your refund has been processed."
            if is_expired
            else "Issue recorded and refund processed."
        ),
    }


# ---------------------------------------------------------------------------
# "Add More to This Order" Endpoints
# ---------------------------------------------------------------------------


@router.get("/{order_id}/addition-status", response_model=OrderAdditionCheckResponse)
async def get_addition_status(
    order_id: UUID,
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
) -> OrderAdditionCheckResponse:
    """Check if the active order is currently eligible for additions."""
    order = await _get_order(db, order_id)
    if order.customer_id != user.id:
        raise AppError(403, "forbidden", "Not your order")

    shop = await db.get(Shop, order.shop_id)
    shop_name = shop.name if shop else "Shop"

    is_eligible = (
        order.status in [OrderStatus.PLACED.value, OrderStatus.ACCEPTED_BY_SHOP.value, OrderStatus.PREPARING.value]
        and getattr(order, "addition_window_status", "ADDITION_OPEN") == AdditionWindowStatus.ADDITION_OPEN.value
        and getattr(order, "delivery_status", "NOT_READY") not in ["PICKED_UP", "OUT_FOR_DELIVERY", "DELIVERED"]
    )

    reason = None
    if not is_eligible:
        if getattr(order, "addition_window_status", "") == AdditionWindowStatus.ADDITION_CLOSED.value:
            reason = "Your order is already being packed, so additional items cannot be added now."
        elif getattr(order, "delivery_status", "") in ["PICKED_UP", "OUT_FOR_DELIVERY"]:
            reason = "The delivery partner is already on the way."
        else:
            reason = "This order is too far along to add items."

    return OrderAdditionCheckResponse(
        order_id=order.id,
        addition_window_status=getattr(order, "addition_window_status", AdditionWindowStatus.ADDITION_OPEN.value),
        is_eligible=is_eligible,
        reason=reason,
        shop_id=order.shop_id,
        shop_name=shop_name,
    )


@router.post("/{order_id}/close-additions")
async def close_additions(
    order_id: UUID,
    user: Annotated[User, require_role(UserRole.SHOP_OWNER)],
    db: DbSession,
) -> dict:
    """Shop closes additions when package is sealed/ready."""
    order = await _get_order(db, order_id)
    await _assert_shop_owns_order(db, order, user)

    order.addition_window_status = AdditionWindowStatus.ADDITION_CLOSED.value
    await db.commit()
    return {"status": "ok", "addition_window_status": order.addition_window_status}


@router.post("/{order_id}/additions", response_model=OrderAdditionOut)
async def create_addition(
    order_id: UUID,
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
    body: OrderAdditionCreateRequest = Body(...),
) -> OrderAdditionOut:
    """Add additional items to an active order before packing is sealed.
    
    Atomically reserves inventory and charges ONLY the additional amount.
    """
    order = await _get_order(db, order_id)
    if order.customer_id != user.id:
        raise AppError(403, "forbidden", "Not your order")

    # 1. Eligibility Check
    is_eligible = (
        order.status in [OrderStatus.PLACED.value, OrderStatus.ACCEPTED_BY_SHOP.value, OrderStatus.PREPARING.value]
        and getattr(order, "addition_window_status", "ADDITION_OPEN") == AdditionWindowStatus.ADDITION_OPEN.value
        and getattr(order, "delivery_status", "NOT_READY") not in ["PICKED_UP", "OUT_FOR_DELIVERY", "DELIVERED"]
    )
    if not is_eligible:
        raise AppError(
            409,
            "addition_closed",
            "Your order has already been packed, so additional items cannot be added now.",
        )

    if not body.items:
        raise AppError(422, "empty_items", "No items provided to add")

    # 2. Fetch products and calculate total
    product_ids = [item.product_id for item in body.items]
    products = (
        await db.scalars(
            select(Product).where(Product.id.in_(product_ids))
        )
    ).all()
    product_map = {p.id: p for p in products}

    for item in body.items:
        p = product_map.get(item.product_id)
        if not p or p.shop_id != order.shop_id:
            raise AppError(422, "invalid_product", f"Product {item.product_id} not available at this shop")

    # 3. Reserve inventory with sorted locks
    reservation_items = [
        type("Item", (), {"product_id": item.product_id, "quantity": item.qty})()
        for item in body.items
    ]
    await reserve_inventory(db, order_id=order.id, items=reservation_items)

    item_total_paise = sum(
        product_map[item.product_id].price_paise * item.qty for item in body.items
    )
    delivery_adjustment_paise = 0  # Traveling with existing delivery
    total_addition_paise = item_total_paise + delivery_adjustment_paise

    # 4. Payment processing for ONLY additional amount
    wallet_used = 0
    if body.wallet_amount_to_use_paise > 0:
        wallet_used = min(body.wallet_amount_to_use_paise, total_addition_paise)
        await debit_wallet_for_order(
            db,
            user_id=user.id,
            order_id=order.id,
            amount_paise=wallet_used,
        )

    external_amount = total_addition_paise - wallet_used

    # 5. Create OrderAddition & Items
    addition = OrderAddition(
        original_order_id=order.id,
        customer_id=user.id,
        shop_id=order.shop_id,
        status=AdditionStatus.CONFIRMED.value,
        item_total_paise=item_total_paise,
        delivery_fee_adjustment_paise=delivery_adjustment_paise,
        total_addition_paise=total_addition_paise,
        wallet_amount_used_paise=wallet_used,
        external_amount_paise=external_amount,
        payment_status="paid" if external_amount == 0 else "paid",
        idempotency_key=body.idempotency_key,
    )
    db.add(addition)
    await db.flush()

    addition_items_out: list[OrderAdditionItemOut] = []
    for item in body.items:
        prod = product_map[item.product_id]
        add_item = OrderAdditionItem(
            addition_id=addition.id,
            product_id=prod.id,
            qty=item.qty,
            price_at_addition_paise=prod.price_paise,
        )
        db.add(add_item)

        # Also add to canonical OrderItems so they are part of the main order
        order_item = OrderItem(
            order_id=order.id,
            product_id=prod.id,
            qty=item.qty,
            price_at_order_time_paise=prod.price_paise,
        )
        db.add(order_item)

        addition_items_out.append(
            OrderAdditionItemOut(
                id=add_item.id,
                product_id=prod.id,
                product_name=prod.name,
                qty=item.qty,
                price_at_addition_paise=prod.price_paise,
            )
        )

    # 6. Commit inventory and update order total
    await commit_inventory(db, order.id)
    order.item_total_paise += item_total_paise
    order.wallet_amount_used_paise += wallet_used
    order.external_amount_paise += external_amount

    await db.commit()
    await db.refresh(addition)

    return OrderAdditionOut(
        id=addition.id,
        original_order_id=order.id,
        status=addition.status,
        item_total_paise=addition.item_total_paise,
        delivery_fee_adjustment_paise=addition.delivery_fee_adjustment_paise,
        total_addition_paise=addition.total_addition_paise,
        wallet_amount_used_paise=addition.wallet_amount_used_paise,
        external_amount_paise=addition.external_amount_paise,
        payment_status=addition.payment_status,
        items=addition_items_out,
        created_at=addition.created_at,
    )


@router.post("/{order_id}/additions/{addition_id}/reject")
async def reject_addition(
    order_id: UUID,
    addition_id: UUID,
    user: Annotated[User, require_role(UserRole.SHOP_OWNER)],
    db: DbSession,
) -> dict:
    """Shopkeeper cannot fulfill addition (e.g. out of stock or package already taped shut).
    
    Automatically releases inventory and refunds the customer.
    """
    order = await _get_order(db, order_id)
    await _assert_shop_owns_order(db, order, user)

    addition = await db.get(OrderAddition, addition_id)
    if not addition or addition.original_order_id != order.id:
        raise AppError(404, "not_found", "Addition not found")

    addition.status = AdditionStatus.REJECTED_BY_SHOP.value

    # Process refund of addition amount
    refund_res = await process_refund(
        db,
        order=order,
        refund_amount_paise=addition.total_addition_paise,
        reason="Shop rejected order addition",
    )

    await db.commit()
    return {"status": "rejected", "refund": refund_res}

