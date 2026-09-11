"""Subscriptions router — authorize mandate, manage subscription."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Body

from app.api.dependencies import DbSession, require_role
from app.domain.enums import UserRole
from app.models.entities import User
from app.services.subscription_service import authorize_subscription

router = APIRouter(prefix="/api/v1/subscriptions", tags=["subscriptions"])


@router.get("/_role-check", include_in_schema=False)
async def role_check(
    user: Annotated[User, require_role(UserRole.SHOP_OWNER)],
) -> dict[str, str]:
    return {"status": "authorized", "role": user.role}


@router.post("/authorize")
async def authorize(
    user: Annotated[User, require_role(UserRole.SHOP_OWNER)],
    db: DbSession,
    shop_id: UUID = Body(..., embed=True),
    plan_id: UUID | None = Body(None, embed=True),
) -> dict:
    """Create a Razorpay Subscription for recurring billing mandate."""
    result = await authorize_subscription(db, shop_id, plan_id)
    return result
