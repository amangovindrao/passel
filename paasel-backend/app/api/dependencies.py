"""Auth dependencies — Supabase JWT → users table role lookup."""

from collections.abc import Callable
from typing import Annotated
from uuid import UUID

import jwt
from fastapi import Depends, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.errors import AppError
from app.core.security import verify_supabase_token
from app.domain.enums import UserRole
from app.models.entities import User

bearer = HTTPBearer(auto_error=False)
DbSession = Annotated[AsyncSession, Depends(get_db)]


async def get_token_payload(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)] = None,
) -> dict:
    """Verify the Supabase JWT and return its claims. No users-table lookup.

    Registration needs this: the caller has a genuine Supabase identity but no
    row in our own users table yet, which is precisely what it is about to
    create. Every other endpoint should depend on get_current_user instead, so
    that an unregistered token cannot reach real business logic.
    """
    if credentials is None:
        raise AppError(
            status.HTTP_401_UNAUTHORIZED,
            "not_authenticated",
            "Authentication required",
        )
    try:
        return verify_supabase_token(credentials.credentials)
    except jwt.InvalidTokenError as exc:
        raise AppError(
            status.HTTP_401_UNAUTHORIZED,
            "invalid_token",
            "Invalid or expired token",
        ) from exc


TokenPayload = Annotated[dict, Depends(get_token_payload)]


async def get_current_user(
    db: DbSession,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)] = None,
) -> User:
    """Verify Supabase JWT, then fetch the canonical role from our users table."""
    if credentials is None:
        raise AppError(
            status.HTTP_401_UNAUTHORIZED,
            "not_authenticated",
            "Authentication required",
        )
    try:
        payload = verify_supabase_token(credentials.credentials)
        user_id = UUID(payload["sub"])
    except (jwt.InvalidTokenError, ValueError, KeyError) as exc:
        raise AppError(
            status.HTTP_401_UNAUTHORIZED,
            "invalid_token",
            "Invalid or expired token",
        ) from exc

    user = await db.scalar(select(User).where(User.id == user_id))
    if user is None:
        # Authenticated with Supabase but never registered with us. The apps
        # answer this by calling POST /api/v1/auth/register, so the code is
        # distinct from a bad token — the client needs to tell them apart.
        raise AppError(
            status.HTTP_401_UNAUTHORIZED,
            "registration_required",
            "Finish signing up to continue",
        )
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]


def require_role(*roles: UserRole) -> Callable:
    """Factory for role-gating dependencies."""

    async def _check(user: CurrentUser) -> User:
        if user.role not in roles:
            raise AppError(
                status.HTTP_403_FORBIDDEN,
                "forbidden",
                f"Requires role: {', '.join(r.value for r in roles)}",
            )
        return user

    return Depends(_check)
