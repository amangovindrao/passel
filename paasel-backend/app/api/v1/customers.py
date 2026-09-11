"""Customer profile CRUD."""

from typing import Annotated

from fastapi import APIRouter, Body
from pydantic import BaseModel

from app.api.dependencies import DbSession, require_role
from app.core.errors import AppError
from app.domain.enums import UserRole
from app.models.entities import CustomerProfile, User
from sqlalchemy import select

router = APIRouter(prefix="/api/v1/customers", tags=["customers"])


class ProfileBody(BaseModel):
    name: str


@router.post("/profile")
async def create_or_update_profile(
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
    body: ProfileBody = Body(...),
) -> dict:
    """Create or update customer profile after first OTP login."""
    existing = await db.scalar(
        select(CustomerProfile).where(CustomerProfile.user_id == user.id)
    )
    if existing:
        existing.name = body.name
    else:
        db.add(CustomerProfile(user_id=user.id, name=body.name))
    await db.commit()
    return {"status": "ok", "name": body.name}


@router.get("/profile")
async def get_profile(
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
) -> dict:
    """Get current customer's profile."""
    profile = await db.scalar(
        select(CustomerProfile).where(CustomerProfile.user_id == user.id)
    )
    if not profile:
        return {"exists": False}
    return {"exists": True, "name": profile.name, "user_id": str(user.id)}
