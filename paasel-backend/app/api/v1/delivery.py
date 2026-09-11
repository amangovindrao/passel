"""Delivery router — delivery_partner only. Phase 3 endpoints."""

from typing import Annotated

from fastapi import APIRouter

from app.api.dependencies import require_role
from app.domain.enums import UserRole
from app.models.entities import User

router = APIRouter(prefix="/api/v1/delivery", tags=["delivery"])


@router.get("/_role-check", include_in_schema=False)
async def role_check(
    user: Annotated[User, require_role(UserRole.DELIVERY_PARTNER)],
) -> dict[str, str]:
    return {"status": "authorized", "role": user.role}
