"""Order placement — quote + create with idempotency, multi-shop bundling, and wallet checkout."""

import random
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Body
from pydantic import BaseModel, Field
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import DbSession, require_role
from app.core.errors import AppError
from app.domain.enums import OrderStatus, OrderType, PaymentMode, UserRole
from app.models.entities import (
    Address,
    Order,
    OrderItem,
    OrderStatusHistory,
    Product,
    Shop,
    User,
)
from app.services.inventory_service import reserve_inventory
from app.services.payment_service import create_razorpay_order
from app.services.wallet_service import (
    debit_wallet_for_order,
    get_or_create_shared_user_wallet,
)

router = APIRouter(prefix="/api/v1/orders", tags=["order-placement"])

MIN_ORDER_PAISE = 9900  # ₹99
SOLO_RATE_PAISE_PER_KM = 2000  # ₹20/km
MIN_DELIVERY_FEE_PAISE = 2000  # ₹20 floor, whatever the rate


# --- Schemas ---


class QuoteRequest(BaseModel):
    shop_id: UUID | None = None
    shop_ids: list[UUID] | None = None
    address_id: UUID


class OrderItemInput(BaseModel):
    product_id: UUID
    qty: int


class ShopCartInput(BaseModel):
    shop_id: UUID
    items: list[OrderItemInput]


class PlaceOrderRequest(BaseModel):
    shop_id: UUID | None = None
    items: list[OrderItemInput] | None = None
    shops: list[ShopCartInput] | None = None
    address_id: UUID
    payment_mode: str = "online"  # "online" | "cod" | "wallet"
    use_wallet: bool = False
    notes: str | None = None
    idempotency_key: UUID


# --- Quote ---


@router.post("/quote")
async def get_quote(
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
    body: QuoteRequest = Body(...),
) -> dict:
    """Compute delivery fee and validate minimum order.

    Supports single-shop or multi-shop quotes with strict 100m proximity check.
    """
    all_shop_ids: list[UUID] = []
    if body.shop_ids:
        all_shop_ids = body.shop_ids
    elif body.shop_id:
        all_shop_ids = [body.shop_id]
    else:
        raise AppError(422, "missing_shop", "shop_id or shop_ids must be provided")

    anchor_id = all_shop_ids[0]
    anchor = await db.get(Shop, anchor_id)
    if not anchor:
        raise AppError(404, "not_found", "Anchor shop not found")

    # Authoritative 100-meter PostGIS validation for multi-shop bundling
    if len(all_shop_ids) > 1:
        for sid in all_shop_ids[1:]:
            s = await db.get(Shop, sid)
            if not s:
                raise AppError(404, "not_found", f"Shop {sid} not found")
            distance_check = await db.scalar(
                text("""
                SELECT ST_Distance(
                    CAST(:anchor_loc AS geography),
                    CAST(:shop_loc AS geography)
                )
            """),
                {"anchor_loc": str(anchor.location), "shop_loc": str(s.location)},
            )
            dist_m = float(distance_check or 0)
            if dist_m > 100.0:
                raise AppError(
                    422,
                    "exceeds_100m_limit",
                    f"Shop {s.name} is {dist_m:.1f}m away from the anchor shop, exceeding the 100m multi-shop limit",
                )

    address = await db.get(Address, body.address_id)
    if not address or address.customer_id != user.id:
        raise AppError(404, "not_found", "Address not found")

    distance_result = await db.scalar(
        text("""
        SELECT ST_Distance(
            CAST(:shop_loc AS geography),
            CAST(:addr_loc AS geography)
        )
    """),
        {"shop_loc": str(anchor.location), "addr_loc": str(address.location)},
    )

    distance_m = float(distance_result or 0) * 1.3  # Route factor
    distance_km = round(distance_m / 1000, 1)

    delivery_fee_paise = max(
        int(SOLO_RATE_PAISE_PER_KM * distance_km), MIN_DELIVERY_FEE_PAISE
    )

    # Customer wallet balance lookup
    wallet = await get_or_create_shared_user_wallet(db, user.id)

    return {
        "distance_km": distance_km,
        "delivery_fee_paise": delivery_fee_paise,
        "delivery_rate_per_km": SOLO_RATE_PAISE_PER_KM,
        "min_order_paise": MIN_ORDER_PAISE,
        "wallet_balance_paise": wallet.balance_paise,
        "bundle_shops_count": len(all_shop_ids),
    }


# --- Place Order ---


@router.post("")
async def place_order(
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
    body: PlaceOrderRequest = Body(...),
) -> dict:
    """Create a single or multi-shop order with idempotency and wallet checkout."""
    # 1. Idempotency check — find existing order with this key
    existing = await db.scalar(
        select(Order).where(
            Order.idempotency_key == str(body.idempotency_key),
        )
    )
    if existing:
        return _order_response(existing)

    # 2. Normalize shop cart groups
    shop_groups: list[ShopCartInput] = []
    if body.shops and len(body.shops) > 0:
        shop_groups = body.shops
    elif body.shop_id and body.items:
        shop_groups = [ShopCartInput(shop_id=body.shop_id, items=body.items)]
    else:
        raise AppError(422, "invalid_cart", "Order must specify shops and items")

    is_multi_shop = len(shop_groups) > 1
    anchor_shop_id = shop_groups[0].shop_id
    anchor_shop = await db.get(Shop, anchor_shop_id)
    if not anchor_shop:
        raise AppError(404, "not_found", "Anchor shop not found")
    if not anchor_shop.is_open:
        raise AppError(
            422, "shop_closed", f"Shop {anchor_shop.name} is currently closed"
        )

    # 3. PostGIS 100m proximity check for all non-anchor shops
    if is_multi_shop:
        for group in shop_groups[1:]:
            s = await db.get(Shop, group.shop_id)
            if not s:
                raise AppError(404, "not_found", f"Shop {group.shop_id} not found")
            if not s.is_open:
                raise AppError(422, "shop_closed", f"Shop {s.name} is currently closed")
            dist_check = await db.scalar(
                text("""
                SELECT ST_Distance(
                    CAST(:anchor_loc AS geography),
                    CAST(:shop_loc AS geography)
                )
            """),
                {"anchor_loc": str(anchor_shop.location), "shop_loc": str(s.location)},
            )
            dist_m = float(dist_check or 0)
            if dist_m > 100.0:
                raise AppError(
                    422,
                    "exceeds_100m_limit",
                    f"Shop {s.name} is {dist_m:.1f}m from anchor shop, which exceeds the 100m bundling limit",
                )

    # 4. Validate address
    address = await db.get(Address, body.address_id)
    if not address or address.customer_id != user.id:
        raise AppError(404, "not_found", "Address not found")

    # 5. Validate and price items per shop server-side
    total_item_paise = 0
    grouped_items: dict[UUID, list[OrderItem]] = {}

    for group in shop_groups:
        shop_items: list[OrderItem] = []
        for item_input in group.items:
            product = await db.get(Product, item_input.product_id)
            if not product or product.shop_id != group.shop_id:
                raise AppError(
                    422,
                    "invalid_item",
                    f"Product {item_input.product_id} does not belong to shop {group.shop_id}",
                )
            if product.stock_status != "available":
                raise AppError(
                    422,
                    "item_unavailable",
                    f"{product.name} is currently out of stock",
                )
            if item_input.qty < 1:
                raise AppError(422, "invalid_qty", "Quantity must be at least 1")

            total_item_paise += product.price_paise * item_input.qty
            shop_items.append(
                OrderItem(
                    product_id=product.id,
                    qty=item_input.qty,
                    price_at_order_time_paise=product.price_paise,
                )
            )
        grouped_items[group.shop_id] = shop_items

    # 6. Minimum order check
    if total_item_paise < MIN_ORDER_PAISE:
        raise AppError(
            422,
            "below_minimum",
            f"Minimum order is ₹{MIN_ORDER_PAISE // 100}, add ₹{(MIN_ORDER_PAISE - total_item_paise) / 100:.2f} more to checkout",
        )

    # 7. Delivery fee from anchor shop
    distance_result = await db.scalar(
        text("""
        SELECT ST_Distance(
            CAST(:shop_loc AS geography),
            CAST(:addr_loc AS geography)
        )
    """),
        {"shop_loc": str(anchor_shop.location), "addr_loc": str(address.location)},
    )
    distance_m = float(distance_result or 0) * 1.3
    distance_km = round(distance_m / 1000, 1)
    delivery_fee_paise = max(
        int(SOLO_RATE_PAISE_PER_KM * distance_km), MIN_DELIVERY_FEE_PAISE
    )

    grand_total_paise = total_item_paise + delivery_fee_paise

    # 8. Shared Wallet Calculation
    wallet = await get_or_create_shared_user_wallet(db, user.id)
    wallet_amount_used = 0
    if body.use_wallet and wallet.balance_paise > 0:
        wallet_amount_used = min(wallet.balance_paise, grand_total_paise)

    remaining_payable_paise = grand_total_paise - wallet_amount_used

    # Determine effective payment mode and status
    if remaining_payable_paise == 0:
        effective_payment_mode = "wallet"
        payment_status = "captured"
    else:
        effective_payment_mode = body.payment_mode
        payment_status = (
            "pending" if effective_payment_mode == "online" else "not_required"
        )

    delivery_otp = f"{random.randint(0, 9999):04d}"

    # 9. Create Parent Order
    parent_order = Order(
        customer_id=user.id,
        shop_id=anchor_shop_id,
        delivery_address_id=address.id,
        status=OrderStatus.PLACED.value,
        order_type=OrderType.MULTI_SHOP_ORDER.value if is_multi_shop else OrderType.NORMAL_ORDER.value,
        item_total_paise=total_item_paise,
        delivery_fee_paise=delivery_fee_paise,
        payment_mode=effective_payment_mode,
        payment_status=payment_status,
        delivery_otp=delivery_otp,
        idempotency_key=str(body.idempotency_key),
        wallet_amount_used_paise=wallet_amount_used,
        external_amount_paise=remaining_payable_paise,
        is_multi_shop=is_multi_shop,
    )
    db.add(parent_order)
    await db.flush()

    # 10. Multi-shop Child Sub-Orders or Single Shop Order Items
    if is_multi_shop:
        for group in shop_groups:
            shop_items = grouped_items[group.shop_id]
            shop_subtotal = sum(
                oi.price_at_order_time_paise * oi.qty for oi in shop_items
            )
            sub_order = Order(
                customer_id=user.id,
                shop_id=group.shop_id,
                delivery_address_id=address.id,
                parent_order_id=parent_order.id,
                status=OrderStatus.PLACED.value,
                order_type=OrderType.MULTI_SHOP_ORDER.value,
                item_total_paise=shop_subtotal,
                delivery_fee_paise=0,  # Single unified delivery fee on parent order
                payment_mode=effective_payment_mode,
                payment_status=payment_status,
                delivery_otp=delivery_otp,
                idempotency_key=f"{body.idempotency_key}_{group.shop_id}",
                wallet_amount_used_paise=0,
                external_amount_paise=shop_subtotal,
                is_multi_shop=False,
            )
            db.add(sub_order)
            await db.flush()

            for oi in shop_items:
                oi.order_id = sub_order.id
                db.add(oi)

            await reserve_inventory(
                db,
                sub_order.id,
                [{"product_id": oi.product_id, "quantity": oi.qty} for oi in shop_items],
            )

            db.add(
                OrderStatusHistory(
                    order_id=sub_order.id, status=OrderStatus.PLACED.value
                )
            )
    else:
        # Single shop order
        for oi in grouped_items[anchor_shop_id]:
            oi.order_id = parent_order.id
            db.add(oi)

        await reserve_inventory(
            db,
            parent_order.id,
            [{"product_id": oi.product_id, "quantity": oi.qty} for oi in grouped_items[anchor_shop_id]],
        )

    db.add(
        OrderStatusHistory(
            order_id=parent_order.id, status=OrderStatus.PLACED.value
        )
    )
    await db.flush()

    # 11. Atomic Wallet Debit via Ledger
    if wallet_amount_used > 0:
        await debit_wallet_for_order(
            db,
            user_id=user.id,
            order_id=parent_order.id,
            amount_paise=wallet_amount_used,
        )

    # 12. Razorpay Order for external remaining payment if online
    razorpay_data = None
    if effective_payment_mode == "online" and remaining_payable_paise > 0:
        try:
            razorpay_data = await create_razorpay_order(db, parent_order)
        except Exception:
            pass

    await db.commit()
    return _order_response(parent_order, razorpay_data=razorpay_data)


def _order_response(
    order: Order, *, razorpay_data: dict | None = None
) -> dict:
    total = order.item_total_paise + order.delivery_fee_paise
    wallet_used = getattr(order, "wallet_amount_used_paise", 0) or 0
    resp: dict = {
        "order_id": str(order.id),
        "status": order.status,
        "item_total_paise": order.item_total_paise,
        "delivery_fee_paise": order.delivery_fee_paise,
        "total_paise": total,
        "wallet_amount_used_paise": wallet_used,
        "remaining_payable_paise": max(0, total - wallet_used),
        "payment_mode": order.payment_mode,
        "payment_status": order.payment_status,
        "is_multi_shop": getattr(order, "is_multi_shop", False),
    }
    if razorpay_data:
        resp.update(razorpay_data)
    return resp
