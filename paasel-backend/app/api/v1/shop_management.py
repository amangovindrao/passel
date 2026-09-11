"""Shop owner profile, shop CRUD, product catalog, toggle-open."""

from datetime import UTC, datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Body, Query
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import DbSession, require_role
from app.core.errors import AppError
from app.domain.enums import (
    ItemAvailability,
    KycStatus,
    OrderStatus,
    PhotoStage,
    SubscriptionStatus,
    UserRole,
)
from app.models.entities import (
    DeliveryAssignment,
    Order,
    OrderItem,
    OrderPhoto,
    Product,
    Shop,
    ShopOwnerProfile,
    ShopSubscription,
    SubscriptionPlan,
    User,
)

router = APIRouter(tags=["shop-management"])


# --- Profile & KYC ---


class ShopOwnerProfileBody(BaseModel):
    name: str


class KycBody(BaseModel):
    id_proof_url: str
    bank_account_number: str | None = None
    bank_ifsc: str | None = None
    upi_id: str | None = None


@router.post("/api/v1/shop-owners/profile")
async def create_shop_owner_profile(
    user: Annotated[User, require_role(UserRole.SHOP_OWNER)],
    db: DbSession,
    body: ShopOwnerProfileBody = Body(...),
) -> dict:
    """Create/update shop owner profile."""
    existing = await db.scalar(
        select(ShopOwnerProfile).where(
            ShopOwnerProfile.user_id == user.id
        )
    )
    if existing:
        existing.name = body.name
    else:
        db.add(ShopOwnerProfile(user_id=user.id, name=body.name))
    await db.commit()
    return {"status": "ok", "name": body.name}


@router.post("/api/v1/shop-owners/kyc")
async def submit_kyc(
    user: Annotated[User, require_role(UserRole.SHOP_OWNER)],
    db: DbSession,
    body: KycBody = Body(...),
) -> dict:
    """Submit KYC docs. Sets kyc_status='pending'."""
    profile = await db.scalar(
        select(ShopOwnerProfile).where(
            ShopOwnerProfile.user_id == user.id
        )
    )
    if not profile:
        raise AppError(404, "no_profile", "Create profile first")

    profile.kyc_status = KycStatus.PENDING.value
    # In production: store document references, trigger admin review
    await db.commit()
    return {"status": "pending", "kyc_status": "pending"}


# --- Shop CRUD ---


class CreateShopBody(BaseModel):
    name: str
    category: str
    lat: float
    lng: float
    address_text: str | None = None
    photo_url: str | None = None


class UpdateShopBody(BaseModel):
    name: str | None = None
    category: str | None = None
    lat: float | None = None
    lng: float | None = None
    photo_url: str | None = None
    is_open: bool | None = None


@router.post("/api/v1/shops")
async def create_shop(
    user: Annotated[User, require_role(UserRole.SHOP_OWNER)],
    db: DbSession,
    body: CreateShopBody = Body(...),
) -> dict:
    """Create shop + start trial subscription."""
    # Check owner doesn't already have a shop
    existing = await db.scalar(
        select(Shop).where(Shop.owner_id == user.id)
    )
    if existing:
        raise AppError(409, "already_exists", "You already have a shop")

    wkt = f"SRID=4326;POINT({body.lng} {body.lat})"
    shop = Shop(
        owner_id=user.id,
        name=body.name,
        category=body.category,
        location=wkt,
        delivery_radius_km=4,
        is_open=False,
        subscription_status=SubscriptionStatus.TRIAL.value,
    )
    db.add(shop)
    await db.flush()

    # Create trial subscription
    starter = await db.scalar(
        select(SubscriptionPlan).where(SubscriptionPlan.name == "Starter")
    )
    if starter:
        now = datetime.now(UTC)
        from datetime import timedelta
        db.add(ShopSubscription(
            shop_id=shop.id,
            plan_id=starter.id,
            is_trial=True,
            trial_start_date=now,
            trial_end_date=now + timedelta(days=30),
        ))

    await db.commit()
    return {
        "shop_id": str(shop.id),
        "status": "created",
        "subscription_status": "trial",
    }


@router.patch("/api/v1/shops/{shop_id}")
async def update_shop(
    shop_id: UUID,
    user: Annotated[User, require_role(UserRole.SHOP_OWNER)],
    db: DbSession,
    body: UpdateShopBody = Body(...),
) -> dict:
    """Edit shop details."""
    shop = await _get_own_shop(db, shop_id, user)
    if body.name is not None:
        shop.name = body.name
    if body.category is not None:
        shop.category = body.category
    if body.lat is not None and body.lng is not None:
        shop.location = f"SRID=4326;POINT({body.lng} {body.lat})"
    await db.commit()
    return {"status": "updated"}


@router.post("/api/v1/shops/{shop_id}/toggle-open")
async def toggle_open(
    shop_id: UUID,
    user: Annotated[User, require_role(UserRole.SHOP_OWNER)],
    db: DbSession,
    is_open: bool = Body(..., embed=True),
) -> dict:
    """Manual open/close override."""
    shop = await _get_own_shop(db, shop_id, user)
    shop.is_open = is_open
    await db.commit()
    return {"is_open": shop.is_open}


@router.get("/api/v1/shops/mine")
async def get_own_shop(
    user: Annotated[User, require_role(UserRole.SHOP_OWNER)],
    db: DbSession,
) -> dict:
    """Get own shop + subscription + kyc status."""
    shop = await db.scalar(
        select(Shop).where(Shop.owner_id == user.id)
    )
    profile = await db.scalar(
        select(ShopOwnerProfile).where(
            ShopOwnerProfile.user_id == user.id
        )
    )
    if not shop:
        return {"exists": False, "kyc_status": profile.kyc_status if profile else "none"}

    sub = await db.scalar(
        select(ShopSubscription)
        .where(ShopSubscription.shop_id == shop.id)
        .order_by(ShopSubscription.created_at.desc())
    )
    return {
        "exists": True,
        "shop_id": str(shop.id),
        "name": shop.name,
        "category": shop.category,
        "is_open": shop.is_open,
        "subscription_status": shop.subscription_status,
        "kyc_status": profile.kyc_status if profile else "none",
        "trial_end_date": (
            sub.trial_end_date.isoformat() if sub and sub.trial_end_date else None
        ),
    }


# --- Product Catalog ---


class CreateProductBody(BaseModel):
    name: str
    category: str | None = None
    price_paise: int
    unit: str
    photo_url: str | None = None


class UpdateProductBody(BaseModel):
    name: str | None = None
    category: str | None = None
    price_paise: int | None = None
    unit: str | None = None
    stock_status: str | None = None
    photo_url: str | None = None


@router.get("/api/v1/shops/{shop_id}/products")
async def list_products_management(
    shop_id: UUID,
    user: Annotated[User, require_role(UserRole.SHOP_OWNER)],
    db: DbSession,
) -> list[dict]:
    """All products (including unavailable) for owner management."""
    shop = await _get_own_shop(db, shop_id, user)
    products = (await db.execute(
        select(Product)
        .where(Product.shop_id == shop.id)
        .order_by(Product.name)
    )).scalars().all()
    return [
        {
            "id": str(p.id),
            "name": p.name,
            "price_paise": p.price_paise,
            "unit": p.unit,
            "stock_status": p.stock_status,
        }
        for p in products
    ]


@router.post("/api/v1/shops/{shop_id}/products")
async def create_product(
    shop_id: UUID,
    user: Annotated[User, require_role(UserRole.SHOP_OWNER)],
    db: DbSession,
    body: CreateProductBody = Body(...),
) -> dict:
    """Add a product to the shop catalog."""
    shop = await _get_own_shop(db, shop_id, user)
    if body.price_paise < 0:
        raise AppError(422, "invalid_price", "Price must be non-negative")

    product = Product(
        shop_id=shop.id,
        name=body.name,
        price_paise=body.price_paise,
        unit=body.unit,
        stock_status="available",
    )
    db.add(product)
    await db.commit()
    await db.refresh(product)
    return {"id": str(product.id), "name": product.name}


@router.patch("/api/v1/products/{product_id}")
async def update_product(
    product_id: UUID,
    user: Annotated[User, require_role(UserRole.SHOP_OWNER)],
    db: DbSession,
    body: UpdateProductBody = Body(...),
) -> dict:
    """Edit a product."""
    product = await db.get(Product, product_id)
    if not product:
        raise AppError(404, "not_found", "Product not found")
    # Verify ownership
    shop = await db.get(Shop, product.shop_id)
    if not shop or shop.owner_id != user.id:
        raise AppError(403, "forbidden", "Not your product")

    if body.name is not None:
        product.name = body.name
    if body.price_paise is not None:
        product.price_paise = body.price_paise
    if body.unit is not None:
        product.unit = body.unit
    if body.stock_status is not None:
        product.stock_status = body.stock_status

    await db.commit()
    return {"status": "updated"}


@router.delete("/api/v1/products/{product_id}")
async def delete_product(
    product_id: UUID,
    user: Annotated[User, require_role(UserRole.SHOP_OWNER)],
    db: DbSession,
) -> dict:
    """Soft-delete a product (mark unavailable)."""
    product = await db.get(Product, product_id)
    if not product:
        raise AppError(404, "not_found", "Product not found")
    shop = await db.get(Shop, product.shop_id)
    if not shop or shop.owner_id != user.id:
        raise AppError(403, "forbidden", "Not your product")

    # Soft-delete: mark as unavailable instead of hard delete
    product.stock_status = "unavailable"
    await db.commit()
    return {"status": "deleted"}


# --- Orders ---
#
# The shop's side of an order lived only in the action endpoints on the orders
# router — accept, reject, mark-ready — with no way to find out an order existed
# in the first place. A shop owner had to be told an order id out of band before
# they could do anything with it, which meant in practice a customer could place
# an order and nobody would ever see it.


# The queue a shop actually works through, in the order they work through it.
# Anything terminal is deliberately absent: this is a worklist, not a ledger,
# and history belongs on a screen nobody has to watch.
_ACTIVE_ORDER_STATUSES = (
    OrderStatus.PLACED.value,
    OrderStatus.ACCEPTED_BY_SHOP.value,
    OrderStatus.PREPARING.value,
    OrderStatus.AWAITING_CUSTOMER_DECISION.value,
    OrderStatus.ON_HOLD.value,
    OrderStatus.READY_FOR_PICKUP.value,
    OrderStatus.PARTNER_ASSIGNED.value,
    OrderStatus.PARTNER_ARRIVED_AT_SHOP.value,
)


@router.get("/api/v1/shops/{shop_id}/orders")
async def list_shop_orders(
    shop_id: UUID,
    user: Annotated[User, require_role(UserRole.SHOP_OWNER)],
    db: DbSession,
    status: str | None = Query(
        None,
        description=(
            "Comma-separated order statuses. Defaults to everything still "
            "needing the shop's attention."
        ),
    ),
    limit: int = Query(50, ge=1, le=200),
) -> list[dict]:
    """The shop's order queue, newest first.

    Newest first because the thing a shop needs to see on opening this screen is
    what just came in. Item counts are aggregated here rather than left to the
    client so the list does not need a request per row.
    """
    shop = await _get_own_shop(db, shop_id, user)

    wanted = _ACTIVE_ORDER_STATUSES
    if status:
        requested = [s.strip() for s in status.split(",") if s.strip()]
        valid = {s.value for s in OrderStatus}
        unknown = [s for s in requested if s not in valid]
        if unknown:
            raise AppError(
                422,
                "invalid_status",
                f"Unknown order status: {', '.join(unknown)}",
            )
        wanted = tuple(requested)

    item_counts = (
        select(
            OrderItem.order_id.label("order_id"),
            func.coalesce(func.sum(OrderItem.qty), 0).label("item_count"),
        )
        .group_by(OrderItem.order_id)
        .subquery()
    )

    rows = (
        await db.execute(
            select(Order, item_counts.c.item_count)
            .outerjoin(item_counts, item_counts.c.order_id == Order.id)
            .where(Order.shop_id == shop.id, Order.status.in_(wanted))
            .order_by(Order.created_at.desc())
            .limit(limit)
        )
    ).all()

    return [
        _order_summary(order, item_count) for order, item_count in rows
    ]


@router.get("/api/v1/shops/{shop_id}/orders/{order_id}")
async def get_shop_order(
    shop_id: UUID,
    order_id: UUID,
    user: Annotated[User, require_role(UserRole.SHOP_OWNER)],
    db: DbSession,
) -> dict:
    """One order with its lines, and what the shop may do about it next.

    `can_mark_ready` is computed server-side rather than inferred by the client.
    The state machine refuses PREPARING -> READY_FOR_PICKUP without a packing
    photo, and a button that looks live but always fails is worse than one that
    is visibly disabled with a reason next to it.
    """
    shop = await _get_own_shop(db, shop_id, user)

    order = await db.get(Order, order_id)
    if not order or order.shop_id != shop.id:
        raise AppError(404, "not_found", "Order not found")

    items = (
        await db.execute(
            select(OrderItem, Product.name, Product.unit)
            .join(Product, Product.id == OrderItem.product_id)
            .where(OrderItem.order_id == order.id)
            .order_by(Product.name)
        )
    ).all()

    has_packing_photo = bool(
        await db.scalar(
            select(func.count())
            .select_from(OrderPhoto)
            .where(
                OrderPhoto.order_id == order.id,
                OrderPhoto.stage == PhotoStage.PACKING.value,
            )
        )
    )

    item_total = sum(
        item.qty * item.price_at_order_time_paise
        for item, _, _ in items
        if item.availability_status != ItemAvailability.UNAVAILABLE.value
    )

    summary = _order_summary(
        order, sum(item.qty for item, _, _ in items)
    )
    summary.update({
        "items": [
            {
                "id": str(item.id),
                "product_id": str(item.product_id),
                "name": name,
                "unit": unit,
                "qty": item.qty,
                "price_paise": item.price_at_order_time_paise,
                "line_total_paise": item.qty * item.price_at_order_time_paise,
                "availability_status": item.availability_status,
                "unavailable_reason": item.unavailable_reason,
            }
            for item, name, unit in items
        ],
        "available_item_total_paise": item_total,
        "has_packing_photo": has_packing_photo,
        "can_accept": order.status == OrderStatus.PLACED.value
        and not _awaiting_online_payment(order),
        "can_mark_ready": order.status == OrderStatus.PREPARING.value
        and has_packing_photo,
        # Only once a rider is actually coming. Before that it is nothing the
        # shop can act on, and it is the customer's code to give away.
        "pickup_code": await _pickup_code(db, order),
    })
    return summary


def _awaiting_online_payment(order: Order) -> bool:
    """An online order nobody has paid for yet cannot be accepted.

    The state machine enforces this too; surfacing it here is what lets the app
    explain the greyed-out button instead of just presenting one that 422s.
    """
    return order.payment_mode == "online" and order.payment_status != "paid"


async def _pickup_code(db: AsyncSession, order: Order) -> str | None:
    if order.status not in (
        OrderStatus.PARTNER_ASSIGNED.value,
        OrderStatus.PARTNER_ARRIVED_AT_SHOP.value,
    ):
        return None
    assignment = await db.scalar(
        select(DeliveryAssignment)
        .where(DeliveryAssignment.order_id == order.id)
        .order_by(DeliveryAssignment.assigned_at.desc())
    )
    return assignment.pickup_code if assignment else None


def _order_summary(order: Order, item_count: int | None) -> dict:
    return {
        "id": str(order.id),
        "status": order.status,
        "item_count": int(item_count or 0),
        "item_total_paise": order.item_total_paise,
        "delivery_fee_paise": order.delivery_fee_paise,
        "total_paise": order.item_total_paise + order.delivery_fee_paise,
        "payment_mode": order.payment_mode,
        "payment_status": order.payment_status,
        "awaiting_payment": _awaiting_online_payment(order),
        "placed_at": order.created_at.isoformat() if order.created_at else None,
    }


# --- Helpers ---


async def _get_own_shop(
    db: AsyncSession, shop_id: UUID, user: User
) -> Shop:
    shop = await db.get(Shop, shop_id)
    if not shop or shop.owner_id != user.id:
        raise AppError(403, "forbidden", "Not your shop")
    return shop
