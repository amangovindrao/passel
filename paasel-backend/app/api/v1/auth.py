"""Auth router — /api/v1/auth

Supabase handles phone-OTP login. What it cannot do is give someone a role in
this system, so registration is the bridge: it turns a verified Supabase
identity into a `users` row plus the profile the rest of the API expects.
"""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Body, Request
from pydantic import BaseModel, Field
from sqlalchemy import select

from app.api.dependencies import CurrentUser, DbSession, TokenPayload, require_role
from app.core.errors import AppError
from app.core.rate_limit import limiter
from app.domain.enums import UserRole
from app.models.entities import (
    CustomerProfile,
    DeliveryPartnerProfile,
    ShopOwnerProfile,
    User,
)
from app.schemas import UserResponse

router = APIRouter(prefix="/api/v1/auth", tags=["auth"])

# Roles a client may claim for itself. `admin` is deliberately absent: it is
# granted out of band, never self-assigned. The other three are safe because
# each app only ever registers its own, and installing a different app is not a
# privilege escalation — it is just being a different kind of user.
_SELF_ASSIGNABLE = {
    UserRole.CUSTOMER.value,
    UserRole.SHOP_OWNER.value,
    UserRole.DELIVERY_PARTNER.value,
}


class RegisterBody(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    role: str


@router.post("/register")
# The apps retry on every launch, and a shared Wi-Fi puts many devices behind
# one address, so this is generous relative to the work it does.
@limiter.limit("30/minute")
async def register(
    request: Request,
    payload: TokenPayload,
    db: DbSession,
    body: RegisterBody = Body(...),
) -> dict:
    """Create the caller's users row and role profile.

    Depends on the raw token rather than the current user, because the whole
    point is that the row does not exist yet.

    Idempotent: calling it again returns the existing account untouched. The
    apps retry this on every launch until it succeeds, so it has to be safe to
    repeat, and it must never silently change someone's role.
    """
    if body.role not in _SELF_ASSIGNABLE:
        raise AppError(422, "invalid_role", f"Cannot register as {body.role}")

    try:
        user_id = UUID(payload["sub"])
    except (KeyError, ValueError) as exc:
        raise AppError(401, "invalid_token", "Token has no subject") from exc

    # The phone comes from the verified token, never from the request body —
    # otherwise anyone could register an account against someone else's number.
    phone = (payload.get("phone") or "").strip()
    if phone and not phone.startswith("+"):
        phone = f"+{phone}"
    if not phone:
        raise AppError(
            422,
            "phone_required",
            "This login has no verified phone number",
        )

    existing = await db.scalar(select(User).where(User.id == user_id))
    if existing is not None:
        await _ensure_profile(db, existing, body.name)
        await db.commit()
        return {
            "user_id": str(existing.id),
            "role": existing.role,
            "created": False,
        }

    # A number can only belong to one account. Supabase enforces one identity
    # per phone, so hitting this means the same number is being reused under a
    # new Supabase user — worth refusing loudly rather than orphaning the old row.
    clash = await db.scalar(select(User).where(User.phone == phone))
    if clash is not None:
        raise AppError(
            409,
            "phone_in_use",
            "That number is already registered",
        )

    user = User(id=user_id, phone=phone, role=body.role)
    db.add(user)
    await db.flush()

    await _ensure_profile(db, user, body.name)
    await db.commit()

    return {"user_id": str(user.id), "role": user.role, "created": True}


@router.get("/me", response_model=UserResponse)
@limiter.limit("30/minute")
async def me(
    request: Request,
    user: Annotated[
        User,
        require_role(
            UserRole.CUSTOMER,
            UserRole.SHOP_OWNER,
            UserRole.DELIVERY_PARTNER,
            UserRole.ADMIN,
        ),
    ],
) -> User:
    return user


@router.get("/registration-status")
async def registration_status(payload: TokenPayload, db: DbSession) -> dict:
    """Whether this Supabase identity has an account here yet.

    Lets a splash screen decide between "resume" and "finish signing up"
    without having to interpret a 401.
    """
    try:
        user_id = UUID(payload["sub"])
    except (KeyError, ValueError):
        return {"registered": False}

    user = await db.scalar(select(User).where(User.id == user_id))
    return {
        "registered": user is not None,
        "role": user.role if user else None,
    }


async def _ensure_profile(db: DbSession, user: User, name: str) -> None:
    """Create the role's profile row if it is missing.

    Each role keeps its details in its own table, and downstream endpoints
    assume that row exists — /shops/mine, /delivery-partners/me and
    /customers/profile all read it. Creating it here means a freshly registered
    user never meets a 404 on their first screen.
    """
    if user.role == UserRole.CUSTOMER.value:
        existing = await db.scalar(
            select(CustomerProfile).where(CustomerProfile.user_id == user.id)
        )
        if existing is None:
            db.add(CustomerProfile(user_id=user.id, name=name))

    elif user.role == UserRole.SHOP_OWNER.value:
        existing = await db.scalar(
            select(ShopOwnerProfile).where(ShopOwnerProfile.user_id == user.id)
        )
        if existing is None:
            db.add(ShopOwnerProfile(user_id=user.id, name=name))

    elif user.role == UserRole.DELIVERY_PARTNER.value:
        existing = await db.scalar(
            select(DeliveryPartnerProfile).where(
                DeliveryPartnerProfile.user_id == user.id
            )
        )
        if existing is None:
            # vehicle_type stays null until the KYC step chooses one.
            db.add(DeliveryPartnerProfile(user_id=user.id, name=name))

    await db.flush()
