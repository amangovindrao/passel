"""Order state machine — single source of truth for all status transitions."""

from collections.abc import Callable, Coroutine
from typing import Any
from uuid import UUID

from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.domain.enums import OrderStatus
from app.models.entities import (
    DeliveryAssignment,
    GroupOrderSession,
    Order,
    OrderPhoto,
    OrderStatusHistory,
)

# Explicit transition map
ALLOWED_TRANSITIONS: dict[OrderStatus, set[OrderStatus]] = {
    OrderStatus.PLACED: {
        OrderStatus.ACCEPTED_BY_SHOP,
        OrderStatus.REJECTED_BY_SHOP,
        OrderStatus.CANCELLED_BY_CUSTOMER,
    },
    OrderStatus.ACCEPTED_BY_SHOP: {OrderStatus.PREPARING},
    OrderStatus.PREPARING: {
        OrderStatus.AWAITING_CUSTOMER_DECISION,
        OrderStatus.READY_FOR_PICKUP,
        OrderStatus.CANCELLED_BY_CUSTOMER,
        OrderStatus.CANCELLED_BY_SHOP,
    },
    OrderStatus.AWAITING_CUSTOMER_DECISION: {
        OrderStatus.PREPARING,
        OrderStatus.ON_HOLD,
        OrderStatus.CANCELLED_ITEM_UNAVAILABLE,
    },
    OrderStatus.ON_HOLD: {OrderStatus.PREPARING},
    OrderStatus.READY_FOR_PICKUP: {OrderStatus.PARTNER_ASSIGNED},
    OrderStatus.PARTNER_ASSIGNED: {OrderStatus.PARTNER_ARRIVED_AT_SHOP},
    OrderStatus.PARTNER_ARRIVED_AT_SHOP: {OrderStatus.PICKED_UP},
    OrderStatus.PICKED_UP: {OrderStatus.OUT_FOR_DELIVERY},
    OrderStatus.OUT_FOR_DELIVERY: {OrderStatus.DELIVERED},
    OrderStatus.DELIVERED: {OrderStatus.COMPLETED},
}

# States at or past PICKED_UP — no customer cancellation allowed
_NO_CANCEL_STATES = {
    OrderStatus.PICKED_UP,
    OrderStatus.OUT_FOR_DELIVERY,
    OrderStatus.DELIVERED,
    OrderStatus.COMPLETED,
}

# Flat cancellation deduction (paise) from PREPARING
CANCELLATION_DEDUCTION_PAISE = 2000  # ₹20

# Event hook type
TransitionHook = Callable[
    [Order, OrderStatus, OrderStatus, AsyncSession],
    Coroutine[Any, Any, None],
]

_hooks: list[TransitionHook] = []


def on_transition(hook: TransitionHook) -> TransitionHook:
    """Register a post-transition hook (notifications, side effects)."""
    _hooks.append(hook)
    return hook


def clear_hooks() -> None:
    """For testing — remove all registered hooks."""
    _hooks.clear()


async def transition(
    db: AsyncSession,
    order: Order,
    to_status: OrderStatus,
    *,
    pickup_code: str | None = None,
    otp: str | None = None,
    actor_id: UUID | None = None,
) -> Order:
    """Transition an order to a new status, enforcing guards.

    Raises:
        AppError 409 if transition is not allowed
        AppError 422 if a guard condition fails
    """
    from_status = OrderStatus(order.status)

    # --- Cancellation policy, checked before the transition map ---
    # Order matters. Cancelling after pickup is not in the transition map
    # either, so the generic "invalid transition" would otherwise fire first and
    # this branch would never run. A customer tapping cancel deserves to be told
    # why — that the parcel is already with a partner — not handed a state-name
    # mismatch.
    if to_status == OrderStatus.CANCELLED_BY_CUSTOMER:
        if from_status in _NO_CANCEL_STATES:
            raise AppError(
                422,
                "cancellation_not_allowed",
                "Cannot cancel after pickup",
            )

    # --- Check transition is allowed ---
    allowed = ALLOWED_TRANSITIONS.get(from_status, set())
    if to_status not in allowed:
        raise AppError(
            409,
            "invalid_transition",
            f"Cannot transition from {from_status.value} to {to_status.value}",
        )

    # --- Payment guard: online orders must be paid before shop acceptance ---
    if from_status == OrderStatus.PLACED and to_status == OrderStatus.ACCEPTED_BY_SHOP:
        if order.payment_mode == "online" and getattr(order, "payment_status", "pending") != "paid":
            raise AppError(
                422,
                "guard_failed",
                "Online order must be paid before shop can accept",
            )

    # --- Guard: PREPARING -> READY_FOR_PICKUP requires packing photo ---
    if from_status == OrderStatus.PREPARING and to_status == OrderStatus.READY_FOR_PICKUP:
        photo_count = await db.scalar(
            select(func.count())
            .select_from(OrderPhoto)
            .where(OrderPhoto.order_id == order.id, OrderPhoto.stage == "packing")
        )
        if not photo_count:
            raise AppError(
                422,
                "guard_failed",
                "Packing photo required before marking ready for pickup",
            )

    # --- Guard: PARTNER_ARRIVED_AT_SHOP -> PICKED_UP requires pickup photo + code ---
    if from_status == OrderStatus.PARTNER_ARRIVED_AT_SHOP and to_status == OrderStatus.PICKED_UP:
        photo_count = await db.scalar(
            select(func.count())
            .select_from(OrderPhoto)
            .where(OrderPhoto.order_id == order.id, OrderPhoto.stage == "pickup")
        )
        if not photo_count:
            raise AppError(422, "guard_failed", "Pickup photo required")
        if not pickup_code:
            raise AppError(422, "guard_failed", "Pickup code required")
        assignment = await db.scalar(
            select(DeliveryAssignment).where(
                DeliveryAssignment.order_id == order.id
            ).order_by(DeliveryAssignment.assigned_at.desc())
        )
        if not assignment or assignment.pickup_code != pickup_code:
            raise AppError(422, "guard_failed", "Invalid pickup code")

    # --- Guard: OUT_FOR_DELIVERY -> DELIVERED requires delivery photo + OTP + payment check ---
    if from_status == OrderStatus.OUT_FOR_DELIVERY and to_status == OrderStatus.DELIVERED:
        photo_count = await db.scalar(
            select(func.count())
            .select_from(OrderPhoto)
            .where(OrderPhoto.order_id == order.id, OrderPhoto.stage == "delivery")
        )
        if not photo_count:
            raise AppError(422, "guard_failed", "Delivery photo required")
        if not otp:
            raise AppError(422, "guard_failed", "Delivery OTP required")
        if order.delivery_otp != otp:
            raise AppError(422, "guard_failed", "Invalid delivery OTP")

        # Payment decoupling guard: unpaid non-COD order cannot be delivered
        if order.payment_mode != "cod" and getattr(order, "payment_status", "pending") != "paid":
            raise AppError(
                422,
                "guard_failed",
                "Order must be paid before delivery",
            )

        # Group Order gate: Rider arriving at group delivery point cannot complete handover
        # if any active member order has not been paid
        if getattr(order, "group_session_id", None):
            session = await db.get(GroupOrderSession, order.group_session_id)
            if session and not getattr(session, "payment_complete", False):
                raise AppError(
                    422,
                    "group_payment_incomplete",
                    "Cannot deliver group order until all active member orders are paid",
                )

    # --- Apply transition ---
    order.status = to_status.value
    db.add(OrderStatusHistory(order_id=order.id, status=to_status.value))
    await db.flush()

    # --- Fire hooks ---
    for hook in _hooks:
        await hook(order, from_status, to_status, db)

    return order
