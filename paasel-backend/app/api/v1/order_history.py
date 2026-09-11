"""Order history, detail, ratings, and disputes."""

from datetime import UTC, datetime, timedelta
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Body, Query
from pydantic import BaseModel
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import DbSession, require_role
from app.core.errors import AppError
from app.domain.enums import OrderStatus, UserRole
from app.models.entities import (
    DeliveryAssignment,
    Dispute,
    Order,
    OrderItem,
    OrderPhoto,
    OrderStatusHistory,
    Rating,
    Refund,
    User,
)

router = APIRouter(prefix="/api/v1/orders", tags=["order-history"])

_TERMINAL_STATUSES = {
    OrderStatus.DELIVERED.value,
    OrderStatus.COMPLETED.value,
    OrderStatus.CANCELLED_BY_CUSTOMER.value,
    OrderStatus.CANCELLED_BY_SHOP.value,
    OrderStatus.CANCELLED_ITEM_UNAVAILABLE.value,
    OrderStatus.REJECTED_BY_SHOP.value,
}

_ACTIVE_STATUSES = {s.value for s in OrderStatus} - _TERMINAL_STATUSES


# --- List Orders ---


@router.get("/history")
async def list_orders(
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
    status: str | None = Query(None),  # "active" | "completed"
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0),
) -> dict:
    """Paginated order history, filterable by active/completed."""
    query = select(Order).where(Order.customer_id == user.id)

    if status == "active":
        query = query.where(Order.status.in_(_ACTIVE_STATUSES))
    elif status == "completed":
        query = query.where(Order.status.in_(_TERMINAL_STATUSES))

    query = query.order_by(Order.created_at.desc()).limit(limit).offset(offset)
    orders = (await db.execute(query)).scalars().all()

    return {
        "orders": [
            {
                "id": str(o.id),
                "shop_id": str(o.shop_id),
                "status": o.status,
                "item_total_paise": o.item_total_paise,
                "delivery_fee_paise": o.delivery_fee_paise,
                "payment_mode": o.payment_mode,
                "created_at": o.created_at.isoformat() if o.created_at else None,
            }
            for o in orders
        ],
        "limit": limit,
        "offset": offset,
    }


# --- Order Detail ---


@router.get("/detail/{order_id}")
async def get_order_detail(
    order_id: UUID,
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
) -> dict:
    """Full order detail: items, pricing, photos, history, ratings."""
    order = await db.get(Order, order_id)
    if not order or order.customer_id != user.id:
        raise AppError(404, "not_found", "Order not found")

    # Items
    items = (await db.execute(
        select(OrderItem).where(OrderItem.order_id == order_id)
    )).scalars().all()

    # Status history
    history = (await db.execute(
        select(OrderStatusHistory)
        .where(OrderStatusHistory.order_id == order_id)
        .order_by(OrderStatusHistory.created_at)
    )).scalars().all()

    # Photos
    photos = (await db.execute(
        select(OrderPhoto)
        .where(OrderPhoto.order_id == order_id)
        .order_by(OrderPhoto.created_at)
    )).scalars().all()

    # Ratings
    ratings = (await db.execute(
        select(Rating).where(Rating.order_id == order_id)
    )).scalars().all()

    # Refunds (for batching discount display)
    refunds = (await db.execute(
        select(Refund).where(Refund.order_id == order_id)
    )).scalars().all()

    # Check if batching refund applied
    batching_refund = next(
        (r for r in refunds if "batch" in (r.reason or "").lower()),
        None,
    )

    return {
        "id": str(order.id),
        "shop_id": str(order.shop_id),
        "status": order.status,
        "item_total_paise": order.item_total_paise,
        "delivery_fee_paise": order.delivery_fee_paise,
        "payment_mode": order.payment_mode,
        "payment_status": order.payment_status,
        "created_at": order.created_at.isoformat() if order.created_at else None,
        "items": [
            {
                "id": str(i.id),
                "product_id": str(i.product_id),
                "qty": i.qty,
                "price_at_order_time_paise": i.price_at_order_time_paise,
                "availability_status": i.availability_status,
                "unavailable_reason": i.unavailable_reason,
            }
            for i in items
        ],
        "status_history": [
            {
                "status": h.status,
                "created_at": h.created_at.isoformat() if h.created_at else None,
            }
            for h in history
        ],
        "photos": [
            {
                "id": str(p.id),
                "stage": p.stage,
                "captured_by": p.captured_by,
                "photo_url": p.photo_url,
                "created_at": p.created_at.isoformat() if p.created_at else None,
            }
            for p in photos
        ],
        "ratings": [
            {
                "rated_entity_type": r.rated_entity_type,
                "score": r.score,
                "comment": r.comment,
            }
            for r in ratings
        ],
        "batching_refund_paise": batching_refund.amount_paise if batching_refund else None,
    }


# --- Tracking (extended) ---


@router.get("/track/{order_id}")
async def get_tracking(
    order_id: UUID,
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
) -> dict:
    """Live tracking: status, partner location, delivery OTP (only after OUT_FOR_DELIVERY)."""
    order = await db.get(Order, order_id)
    if not order or order.customer_id != user.id:
        raise AppError(404, "not_found", "Order not found")

    response: dict = {
        "order_id": str(order.id),
        "status": order.status,
        "shop_id": str(order.shop_id),
    }

    # Status history for timeline
    history = (await db.execute(
        select(OrderStatusHistory)
        .where(OrderStatusHistory.order_id == order_id)
        .order_by(OrderStatusHistory.created_at)
    )).scalars().all()
    response["status_history"] = [
        {"status": h.status, "created_at": h.created_at.isoformat() if h.created_at else None}
        for h in history
    ]

    # Partner info + location
    assignment = await db.scalar(
        select(DeliveryAssignment)
        .where(DeliveryAssignment.order_id == order_id)
        .order_by(DeliveryAssignment.assigned_at.desc())
    )
    if assignment:
        response["partner_id"] = str(assignment.partner_id)
        from app.models.entities import LiveLocation
        live = await db.get(LiveLocation, assignment.partner_id)
        if live:
            response["partner_location_updated_at"] = (
                live.updated_at.isoformat() if live.updated_at else None
            )

    # Delivery OTP: ONLY when OUT_FOR_DELIVERY or later
    otp_visible_states = {
        OrderStatus.OUT_FOR_DELIVERY.value,
        OrderStatus.DELIVERED.value,
        OrderStatus.COMPLETED.value,
    }
    if order.status in otp_visible_states:
        response["delivery_otp"] = order.delivery_otp

    return response


# --- Ratings ---


class RatingBody(BaseModel):
    rated_entity_type: str  # "shop" | "delivery_partner"
    score: int
    comment: str | None = None


@router.post("/rate/{order_id}")
async def rate_order(
    order_id: UUID,
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
    body: RatingBody = Body(...),
) -> dict:
    """Rate shop or delivery partner for this order."""
    order = await db.get(Order, order_id)
    if not order or order.customer_id != user.id:
        raise AppError(404, "not_found", "Order not found")

    if order.status not in _TERMINAL_STATUSES:
        raise AppError(422, "order_not_complete", "Can only rate completed orders")

    if body.rated_entity_type not in ("shop", "delivery_partner"):
        raise AppError(422, "invalid_entity", "Must be shop or delivery_partner")

    if body.score < 1 or body.score > 5:
        raise AppError(422, "invalid_score", "Score must be 1-5")

    # Check not already rated this entity
    existing = await db.scalar(
        select(Rating).where(
            Rating.order_id == order_id,
            Rating.rated_by == user.id,
            Rating.rated_entity_type == body.rated_entity_type,
        )
    )
    if existing:
        raise AppError(409, "already_rated", "Already rated this entity for this order")

    db.add(Rating(
        order_id=order_id,
        rated_by=user.id,
        rated_entity_type=body.rated_entity_type,
        score=body.score,
        comment=body.comment,
    ))
    await db.commit()
    return {"status": "rated"}


# --- Disputes ---


class DisputeBody(BaseModel):
    reason: str
    comment: str | None = None


@router.post("/dispute/{order_id}")
async def raise_dispute(
    order_id: UUID,
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
    body: DisputeBody = Body(...),
) -> dict:
    """Raise a dispute within 48h of delivery."""
    order = await db.get(Order, order_id)
    if not order or order.customer_id != user.id:
        raise AppError(404, "not_found", "Order not found")

    if order.status not in (OrderStatus.DELIVERED.value, OrderStatus.COMPLETED.value):
        raise AppError(422, "not_delivered", "Can only dispute delivered orders")

    # 48h window check
    if order.updated_at:
        cutoff = order.updated_at + timedelta(hours=48)
        if datetime.now(UTC) > cutoff:
            raise AppError(
                422, "window_closed",
                "Dispute window (48h) has passed. Please contact support.",
            )

    db.add(Dispute(
        order_id=order_id,
        raised_by=user.id,
        status="open",
        resolution=None,
        linked_photo_ids=None,
    ))
    await db.commit()
    return {"status": "dispute_raised"}
