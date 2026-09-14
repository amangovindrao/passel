"""Payment service — create orders, process webhooks, handle refunds."""

import hashlib
import hmac
from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.errors import AppError
from app.domain.enums import OrderStatus, PaymentMode, PaymentStatus
from app.models.entities import Order, Payment, Refund
from app.services.razorpay_client import razorpay


# --- Webhook event deduplication ---
_processed_events: set[str] = set()  # In production, use a DB table


def verify_webhook_signature(body: bytes, signature: str) -> bool:
    """Verify Razorpay webhook HMAC-SHA256 signature."""
    secret = settings.razorpay_key_secret.encode()
    expected = hmac.new(secret, body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature)


def is_event_processed(event_id: str) -> bool:
    return event_id in _processed_events


def mark_event_processed(event_id: str) -> None:
    _processed_events.add(event_id)


def clear_processed_events() -> None:
    """For testing."""
    _processed_events.clear()


async def create_razorpay_order(
    db: AsyncSession,
    order: Order,
) -> dict:
    """Create a Razorpay order for the given Paasel order."""
    total = order.item_total_paise + order.delivery_fee_paise
    wallet_used = getattr(order, "wallet_amount_used_paise", 0) or 0
    amount = max(0, total - wallet_used)
    rz_order = await razorpay.create_order(
        amount_paise=amount,
        receipt=str(order.id),
        notes={"paasel_order_id": str(order.id)},
    )
    return {
        "razorpay_order_id": rz_order["id"],
        "razorpay_key_id": settings.razorpay_key_id,
        "amount_paise": amount,
        "currency": "INR",
    }


async def handle_payment_captured(
    db: AsyncSession,
    razorpay_payment_id: str,
    razorpay_order_id: str,
    amount_paise: int,
    notes: dict,
) -> None:
    """Process payment.captured webhook event."""
    paasel_order_id = notes.get("paasel_order_id")
    if not paasel_order_id:
        return

    order = await db.get(Order, UUID(paasel_order_id))
    if not order:
        return

    # Create payment record
    existing = await db.scalar(
        select(Payment).where(Payment.razorpay_payment_id == razorpay_payment_id)
    )
    if existing:
        return  # Already processed

    db.add(Payment(
        order_id=order.id,
        razorpay_payment_id=razorpay_payment_id,
        amount_paise=amount_paise,
        status=PaymentStatus.CAPTURED.value,
    ))

    # Mark order as paid — this makes it visible to the shop
    order.payment_status = "paid"
    await db.commit()


async def handle_payment_failed(
    db: AsyncSession,
    razorpay_payment_id: str,
    notes: dict,
) -> None:
    """Process payment.failed webhook event."""
    paasel_order_id = notes.get("paasel_order_id")
    if not paasel_order_id:
        return

    order = await db.get(Order, UUID(paasel_order_id))
    if not order:
        return

    db.add(Payment(
        order_id=order.id,
        razorpay_payment_id=razorpay_payment_id,
        amount_paise=0,
        status=PaymentStatus.FAILED.value,
    ))
    order.payment_status = "failed"
    await db.commit()

    # Schedule auto-cancel after 15 min if still not paid
    from app.workers.tasks import payment_expiry_check
    payment_expiry_check.apply_async(args=[str(order.id)], countdown=900)


async def handle_refund_processed(
    db: AsyncSession,
    razorpay_refund_id: str,
    razorpay_payment_id: str,
    amount_paise: int,
) -> None:
    """Process refund.processed webhook event."""
    # Find the pending refund and mark it processed
    refund = await db.scalar(
        select(Refund).where(Refund.razorpay_refund_id == razorpay_refund_id)
    )
    if refund:
        refund.status = "processed"
    else:
        # Find by payment -> order
        payment = await db.scalar(
            select(Payment).where(Payment.razorpay_payment_id == razorpay_payment_id)
        )
        if payment:
            # Update any pending refund for this order
            pending_refund = await db.scalar(
                select(Refund).where(
                    Refund.order_id == payment.order_id,
                    Refund.status == "pending",
                )
            )
            if pending_refund:
                pending_refund.razorpay_refund_id = razorpay_refund_id
                pending_refund.status = "processed"
    await db.commit()


async def initiate_partial_refund(
    db: AsyncSession,
    order: Order,
    refund_amount_paise: int,
    reason: str = "Partial refund for unavailable items",
) -> Refund | None:
    """Initiate a partial refund (online orders only).

    Returns None for COD orders: there is nothing to refund because the amount
    collected on delivery is simply the reduced total.
    """
    if order.payment_mode != PaymentMode.ONLINE.value:
        return None

    # Find the captured payment
    payment = await db.scalar(
        select(Payment).where(
            Payment.order_id == order.id,
            Payment.status == PaymentStatus.CAPTURED.value,
        )
    )
    if not payment or not payment.razorpay_payment_id:
        # No payment to refund — create pending record for manual resolution
        refund = Refund(
            order_id=order.id,
            amount_paise=refund_amount_paise,
            reason=reason,
            status="pending",
        )
        db.add(refund)
        return refund

    # Call Razorpay
    try:
        rz_refund = await razorpay.create_partial_refund(
            payment_id=payment.razorpay_payment_id,
            amount_paise=refund_amount_paise,
            notes={"paasel_order_id": str(order.id), "reason": reason},
        )
        refund = Refund(
            order_id=order.id,
            razorpay_refund_id=rz_refund.get("id"),
            amount_paise=refund_amount_paise,
            reason=reason,
            status="pending",  # Confirmed by webhook
        )
    except Exception:
        # API call failed — create pending for retry
        refund = Refund(
            order_id=order.id,
            amount_paise=refund_amount_paise,
            reason=reason,
            status="pending",
        )

    db.add(refund)
    return refund
