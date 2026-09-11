"""Payments router — create Razorpay orders, webhook handler."""

import hashlib
import hmac
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Body, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import DbSession, require_role
from app.core.config import settings
from app.core.errors import AppError
from app.domain.enums import UserRole
from app.models.entities import Order, User
from app.services.payment_service import (
    create_razorpay_order,
    handle_payment_captured,
    handle_payment_failed,
    handle_refund_processed,
    is_event_processed,
    mark_event_processed,
    verify_webhook_signature,
)

router = APIRouter(prefix="/api/v1/payments", tags=["payments"])


@router.get("/_role-check", include_in_schema=False)
async def role_check(
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
) -> dict[str, str]:
    return {"status": "authorized", "role": user.role}


@router.post("/create-order")
async def create_payment_order(
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
    order_id: UUID = Body(..., embed=True),
) -> dict:
    """Create a Razorpay Order for checkout."""
    order = await db.get(Order, order_id)
    if not order:
        raise AppError(404, "not_found", "Order not found")
    if order.customer_id != user.id:
        raise AppError(403, "forbidden", "Not your order")
    if order.payment_mode != "online":
        raise AppError(422, "invalid_payment_mode", "Only online orders need payment")

    result = await create_razorpay_order(db, order)
    return result


@router.post("/webhooks/razorpay", include_in_schema=False)
async def razorpay_webhook(request: Request, db: DbSession) -> dict:
    """Handle Razorpay webhook events — signature-verified, idempotent."""
    body = await request.body()
    signature = request.headers.get("X-Razorpay-Signature", "")

    # Verify HMAC-SHA256 signature
    secret = settings.razorpay_key_secret.encode()
    expected = hmac.new(secret, body, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(expected, signature):
        raise AppError(400, "invalid_signature", "Webhook signature verification failed")

    import json
    payload = json.loads(body)
    event = payload.get("event", "")
    event_id = payload.get("id", "")

    # Idempotency check
    if is_event_processed(event_id):
        return {"status": "already_processed"}
    mark_event_processed(event_id)

    # Route events
    entity = payload.get("payload", {})

    if event == "payment.captured":
        payment_entity = entity.get("payment", {}).get("entity", {})
        await handle_payment_captured(
            db,
            razorpay_payment_id=payment_entity.get("id", ""),
            razorpay_order_id=payment_entity.get("order_id", ""),
            amount_paise=payment_entity.get("amount", 0),
            notes=payment_entity.get("notes", {}),
        )
    elif event == "payment.failed":
        payment_entity = entity.get("payment", {}).get("entity", {})
        await handle_payment_failed(
            db,
            razorpay_payment_id=payment_entity.get("id", ""),
            notes=payment_entity.get("notes", {}),
        )
    elif event == "refund.processed":
        refund_entity = entity.get("refund", {}).get("entity", {})
        await handle_refund_processed(
            db,
            razorpay_refund_id=refund_entity.get("id", ""),
            razorpay_payment_id=refund_entity.get("payment_id", ""),
            amount_paise=refund_entity.get("amount", 0),
        )
    elif event == "subscription.charged":
        sub_entity = entity.get("subscription", {}).get("entity", {})
        from app.services.subscription_service import handle_subscription_charged
        await handle_subscription_charged(db, sub_entity.get("id", ""))

    return {"status": "processed"}
