"""Mint a local dev JWT and, optionally, the backing users row.

The apps get their token from Supabase. This script produces an equivalent one
signed with the same secret, so the API can be exercised from /docs or curl
without a Supabase project.

    python scripts/dev_token.py --role customer --seed

`--seed` inserts the matching `users` row. Without it the token verifies but
every call returns 401 user_not_found, because nothing in the codebase creates
that row — see the note in the project README.

Dev only. It signs with SUPABASE_JWT_SECRET, which in a real deployment is a
production secret; never run this against anything but a local stack.
"""

from __future__ import annotations

import argparse
import asyncio
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import jwt

from app.core.config import settings
from app.domain.enums import UserRole


def mint(user_id: UUID, phone: str, hours: int) -> str:
    now = datetime.now(UTC)
    return jwt.encode(
        {
            "sub": str(user_id),
            "aud": "authenticated",
            "iss": settings.supabase_issuer,
            "role": "authenticated",
            "phone": phone,
            "iat": int(now.timestamp()),
            "exp": int((now + timedelta(hours=hours)).timestamp()),
        },
        settings.supabase_jwt_secret,
        algorithm="HS256",
    )


async def seed_user(user_id: UUID, phone: str, role: str) -> str:
    from sqlalchemy import select

    from app.core.database import SessionFactory
    from app.models.entities import User

    async with SessionFactory() as db:
        existing = await db.scalar(select(User).where(User.id == user_id))
        if existing:
            return "already present"
        db.add(User(id=user_id, phone=phone, role=role))
        await db.commit()
        return "inserted"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--role",
        default=UserRole.CUSTOMER.value,
        choices=[r.value for r in UserRole],
    )
    parser.add_argument("--user-id", default=None)
    parser.add_argument("--phone", default=None)
    parser.add_argument("--hours", type=int, default=12)
    parser.add_argument(
        "--seed",
        action="store_true",
        help="also insert the users row the API requires",
    )
    args = parser.parse_args()

    user_id = UUID(args.user_id) if args.user_id else uuid4()
    phone = args.phone or f"+9199{uuid4().int % 10**8:08d}"

    token = mint(user_id, phone, args.hours)

    if args.seed:
        outcome = asyncio.run(seed_user(user_id, phone, args.role))
        print(f"users row: {outcome}")

    print(f"user_id  : {user_id}")
    print(f"phone    : {phone}")
    print(f"role     : {args.role}")
    print(f"expires  : {args.hours}h")
    print()
    print(token)


if __name__ == "__main__":
    main()
