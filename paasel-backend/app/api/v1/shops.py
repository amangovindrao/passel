"""Shops router — discovery + detail for customers, role-check for owners."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Query
from sqlalchemy import text, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import DbSession, require_role
from app.core.errors import AppError
from app.domain.enums import UserRole
from app.models.entities import Product, Shop, User

router = APIRouter(prefix="/api/v1/shops", tags=["shops"])


@router.get("/_role-check", include_in_schema=False)
async def role_check(
    user: Annotated[User, require_role(UserRole.SHOP_OWNER)],
) -> dict[str, str]:
    return {"status": "authorized", "role": user.role}


@router.get("/nearby")
async def nearby_shops(
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
    lat: float = Query(...),
    lng: float = Query(...),
    search: str | None = Query(None),
) -> list[dict]:
    """Find shops that deliver to the given point.

    Returns shops where the customer's location is within shop's delivery_radius_km.
    Ordered: open-first, then by distance.
    """
    search_clause = ""
    params: dict = {"lat": lat, "lng": lng}

    if search:
        search_clause = "AND (s.name ILIKE :search OR s.category ILIKE :search)"
        params["search"] = f"%{search}%"

    query = text(f"""
        SELECT
            s.id, s.name, s.category, s.is_open,
            s.delivery_radius_km,
            ST_Distance(
                s.location,
                ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography
            ) AS distance_m
        FROM shops s
        JOIN shop_owner_profiles sop ON sop.user_id = s.owner_id
        WHERE s.subscription_status NOT IN ('suspended')
          AND sop.kyc_status = 'approved'
          AND ST_DWithin(
              s.location,
              ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography,
              s.delivery_radius_km * 1000
          )
          {search_clause}
        ORDER BY s.is_open DESC, distance_m ASC
        LIMIT 50
    """)

    rows = (await db.execute(query, params)).all()
    return [
        {
            "id": str(row.id),
            "name": row.name,
            "category": row.category,
            "is_open": row.is_open,
            "distance_m": round(row.distance_m, 0),
            "delivery_radius_km": row.delivery_radius_km,
        }
        for row in rows
    ]


@router.get("/{shop_id}")
async def get_shop_detail(
    shop_id: UUID,
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
) -> dict:
    """Shop detail + products grouped by category."""
    shop = await db.get(Shop, shop_id)
    if not shop:
        raise AppError(404, "not_found", "Shop not found")

    products = (await db.execute(
        select(Product)
        .where(Product.shop_id == shop_id)
        .order_by(Product.name)
    )).scalars().all()

    # Group by unit (used as category placeholder — in production would be a category field)
    grouped: dict[str, list[dict]] = {}
    for p in products:
        cat = p.unit or "General"
        if cat not in grouped:
            grouped[cat] = []
        grouped[cat].append({
            "id": str(p.id),
            "name": p.name,
            "price_paise": p.price_paise,
            "stock_status": p.stock_status,
        })

    return {
        "id": str(shop.id),
        "name": shop.name,
        "category": shop.category,
        "is_open": shop.is_open,
        "delivery_radius_km": shop.delivery_radius_km,
        "subscription_status": shop.subscription_status,
        "products": grouped,
    }
