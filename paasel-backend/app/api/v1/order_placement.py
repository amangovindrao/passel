"""Order placement — quote + create with idempotency."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Body
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import DbSession, require_role
from app.core.errors import AppError
from app.domain.enums import OrderStatus, PaymentMode, UserRole
from app.models.entities import (
    Address,
    Order,
    OrderItem,
    OrderStatusHistory,
    Product,
    Shop,
    User,
)
from app.services.payment_service import create_razorpay_order

router = APIRouter(prefix="/api/v1/orders", tags=["order-placement"])

MIN_ORDER_PAISE = 9900  # ₹99
SOLO_RATE_PAISE_PER_KM = 2000  # ₹20/km
MIN_DELIVERY_FEE_PAISE = 2000  # ₹20 floor, whatever the rate


# --- Schemas ---


class QuoteRequest(BaseModel):
    shop_id: UUID
    address_id: UUID


class OrderItemInput(BaseModel):
    product_id: UUID
    qty: int


class PlaceOrderRequest(BaseModel):
    shop_id: UUID
    address_id: UUID
    items: list[OrderItemInput]
    payment_mode: str  # "online" | "cod"
    notes: str | None = None
    idempotency_key: UUID


# --- Quote ---


@router.post("/quote")
async def get_quote(
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
    body: QuoteRequest = Body(...),
) -> dict:
    """Compute delivery fee and validate minimum order."""
    shop = await db.get(Shop, body.shop_id)
    if not shop:
        raise AppError(404, "not_found", "Shop not found")

    address = await db.get(Address, body.address_id)
    if not address or address.customer_id != user.id:
        raise AppError(404, "not_found", "Address not found")

    # Compute route distance (in production: Google Directions API)
    # For now, use PostGIS straight-line as approximation × 1.3 factor
    from sqlalchemy import text
    distance_result = await db.scalar(text("""
        SELECT ST_Distance(
            CAST(:shop_loc AS geography),
            CAST(:addr_loc AS geography)
        )
    """), {"shop_loc": str(shop.location), "addr_loc": str(address.location)})

    distance_m = float(distance_result or 0) * 1.3  # Route factor
    distance_km = round(distance_m / 1000, 1)

    delivery_fee_paise = max(
        int(SOLO_RATE_PAISE_PER_KM * distance_km), MIN_DELIVERY_FEE_PAISE
    )

    # Get cart items total from the user's perspective
    # (actual validation happens at placement time)
    return {
        "distance_km": distance_km,
        "delivery_fee_paise": delivery_fee_paise,
        "delivery_rate_per_km": SOLO_RATE_PAISE_PER_KM,
        "min_order_paise": MIN_ORDER_PAISE,
    }


# --- Place Order ---


@router.post("")
async def place_order(
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
    body: PlaceOrderRequest = Body(...),
) -> dict:
    """Create an order with idempotency protection."""
    # Idempotency check — find existing order with this key
    existing = await db.scalar(
        select(Order).where(
            Order.idempotency_key == str(body.idempotency_key),
        )
    )
    if existing:
        return _order_response(existing)

    # Validate shop
    shop = await db.get(Shop, body.shop_id)
    if not shop:
        raise AppError(404, "not_found", "Shop not found")
    if not shop.is_open:
        raise AppError(422, "shop_closed", "Shop is currently closed")

    # Validate address
    address = await db.get(Address, body.address_id)
    if not address or address.customer_id != user.id:
        raise AppError(404, "not_found", "Address not found")

    # Validate payment mode
    if body.payment_mode not in ("online", "cod"):
        raise AppError(422, "invalid_payment_mode", "Must be online or cod")

    # Validate and price items server-side
    item_total_paise = 0
    order_items: list[OrderItem] = []
    for item_input in body.items:
        product = await db.get(Product, item_input.product_id)
        if not product or product.shop_id != body.shop_id:
            raise AppError(
                422, "invalid_item",
                f"Product {item_input.product_id} not found in this shop",
            )
        if product.stock_status != "available":
            raise AppError(
                422, "item_unavailable",
                f"{product.name} is currently unavailable",
            )
        if item_input.qty < 1:
            raise AppError(422, "invalid_qty", "Quantity must be at least 1")

        line_total = product.price_paise * item_input.qty
        item_total_paise += line_total
        order_items.append(OrderItem(
            product_id=product.id,
            qty=item_input.qty,
            price_at_order_time_paise=product.price_paise,
        ))

    # Minimum order check
    if item_total_paise < MIN_ORDER_PAISE:
        raise AppError(
            422, "below_minimum",
            f"Minimum order is {MIN_ORDER_PAISE} paise, "
            f"need {MIN_ORDER_PAISE - item_total_paise} more",
        )

    # Compute delivery fee (same as quote)
    from sqlalchemy import text
    distance_result = await db.scalar(text("""
        SELECT ST_Distance(
            CAST(:shop_loc AS geography),
            CAST(:addr_loc AS geography)
        )
    """), {"shop_loc": str(shop.location), "addr_loc": str(address.location)})
    distance_m = float(distance_result or 0) * 1.3
    distance_km = round(distance_m / 1000, 1)
    delivery_fee_paise = max(
        int(SOLO_RATE_PAISE_PER_KM * distance_km), MIN_DELIVERY_FEE_PAISE
    )

    # Generate 4-digit delivery OTP
    import random
    delivery_otp = f"{random.randint(0, 9999):04d}"

    # Determine payment status
    payment_status = (
        "pending" if body.payment_mode == "online" else "not_required"
    )

    # Create order
    order = Order(
        customer_id=user.id,
        shop_id=body.shop_id,
        delivery_address_id=address.id,
        status=OrderStatus.PLACED.value,
        item_total_paise=item_total_paise,
        delivery_fee_paise=delivery_fee_paise,
        payment_mode=body.payment_mode,
        payment_status=payment_status,
        delivery_otp=delivery_otp,
        idempotency_key=str(body.idempotency_key),
    )
    db.add(order)
    await db.flush()

    # Attach items
    for oi in order_items:
        oi.order_id = order.id
        db.add(oi)

    # Initial status history
    db.add(OrderStatusHistory(
        order_id=order.id, status=OrderStatus.PLACED.value,
    ))

    await db.flush()

    # For online: create Razorpay order
    razorpay_data = None
    if body.payment_mode == "online":
        try:
            razorpay_data = await create_razorpay_order(db, order)
        except Exception:
            # If Razorpay fails, still create the order — client can retry
            pass

    await db.commit()
    return _order_response(order, razorpay_data=razorpay_data)


def _order_response(
    order: Order, *, razorpay_data: dict | None = None
) -> dict:
    resp: dict = {
        "order_id": str(order.id),
        "status": order.status,
        "item_total_paise": order.item_total_paise,
        "delivery_fee_paise": order.delivery_fee_paise,
        "total_paise": order.item_total_paise + order.delivery_fee_paise,
        "payment_mode": order.payment_mode,
        "payment_status": order.payment_status,
    }
    if razorpay_data:
        resp.update(razorpay_data)
    return resp
