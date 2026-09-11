"""Missing-item flow — unavailability handling and customer decision."""

from uuid import UUID

from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.domain.enums import ItemAvailability, OrderStatus, PaymentMode
from app.models.entities import Order, OrderItem, Refund
from app.services.order_state_machine import transition


async def mark_item_unavailable(
    db: AsyncSession,
    order: Order,
    item_id: UUID,
    reason: str,
) -> Order:
    """Shop marks an item unavailable; transitions order if needed."""
    item = await db.scalar(
        select(OrderItem).where(
            OrderItem.id == item_id,
            OrderItem.order_id == order.id,
        )
    )
    if not item:
        raise AppError(404, "item_not_found", "Order item not found")

    item.availability_status = ItemAvailability.UNAVAILABLE.value
    item.unavailable_reason = reason

    # Transition to AWAITING_CUSTOMER_DECISION if still PREPARING
    current = OrderStatus(order.status)
    if current == OrderStatus.PREPARING:
        order = await transition(db, order, OrderStatus.AWAITING_CUSTOMER_DECISION)
    # If already AWAITING_CUSTOMER_DECISION, no extra transition needed

    return order


async def compute_revised_total(db: AsyncSession, order: Order) -> int:
    """Compute item_total minus unavailable items."""
    available_total = await db.scalar(
        select(func.coalesce(func.sum(OrderItem.price_at_order_time_paise * OrderItem.qty), 0))
        .where(
            OrderItem.order_id == order.id,
            OrderItem.availability_status == ItemAvailability.AVAILABLE.value,
        )
    )
    return int(available_total or 0)


async def handle_customer_decision(
    db: AsyncSession,
    order: Order,
    decision: str,
) -> Order:
    """Process customer's response to missing items.

    Decisions:
    - proceed: continue with available items, queue partial refund if online
    - hold: move to ON_HOLD (7-min timeout will auto-proceed)
    - cancel: cancel the order entirely
    """
    current = OrderStatus(order.status)
    if current not in (OrderStatus.AWAITING_CUSTOMER_DECISION, OrderStatus.ON_HOLD):
        raise AppError(
            409,
            "invalid_state",
            f"Cannot handle decision in state {current.value}",
        )

    if decision == "proceed":
        return await _proceed(db, order)
    elif decision == "hold":
        return await transition(db, order, OrderStatus.ON_HOLD)
    elif decision == "cancel":
        return await transition(db, order, OrderStatus.CANCELLED_ITEM_UNAVAILABLE)
    else:
        raise AppError(422, "invalid_decision", "Decision must be proceed, hold, or cancel")


async def _proceed(db: AsyncSession, order: Order) -> Order:
    """Continue with available items and queue refund for unavailable ones."""
    revised = await compute_revised_total(db, order)
    diff = order.item_total_paise - revised

    # Queue partial refund if online payment and there's a difference
    if diff > 0 and order.payment_mode == PaymentMode.ONLINE.value:
        db.add(Refund(
            order_id=order.id,
            amount_paise=diff,
            reason="Partial refund for unavailable items",
            status="pending",
        ))

    # Update order total
    order.item_total_paise = revised

    # Transition back to PREPARING
    return await transition(db, order, OrderStatus.PREPARING)


async def auto_proceed_on_timeout(db: AsyncSession, order_id: UUID) -> None:
    """Called by Celery after 7 minutes — auto-proceeds if still waiting."""
    order = await db.get(Order, order_id)
    if not order:
        return

    current = OrderStatus(order.status)
    if current in (OrderStatus.AWAITING_CUSTOMER_DECISION, OrderStatus.ON_HOLD):
        await _proceed(db, order)
        await db.commit()
