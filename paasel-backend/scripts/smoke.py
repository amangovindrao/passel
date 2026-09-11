"""Local smoke test: seed a user, then walk the authenticated API.

Proves the stack is actually wired up end to end without needing a Supabase
project or a running app. Dev only.

    python scripts/smoke.py
"""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import httpx
import jwt
from sqlalchemy import select

from app.core.config import settings
from app.core.database import SessionFactory
from app.models.entities import User

BASE_URL = "http://127.0.0.1:8000"


def mint(user_id, phone: str) -> str:
    now = datetime.now(UTC)
    return jwt.encode(
        {
            "sub": str(user_id),
            "aud": "authenticated",
            "iss": settings.supabase_issuer,
            "role": "authenticated",
            "phone": phone,
            "iat": int(now.timestamp()),
            "exp": int((now + timedelta(hours=8)).timestamp()),
        },
        settings.supabase_jwt_secret,
        algorithm="HS256",
    )


async def main() -> None:
    uid = uuid4()
    phone = f"+9199{uuid4().int % 10**8:08d}"
    token = mint(uid, phone)

    async with SessionFactory() as db:
        db.add(User(id=uid, phone=phone, role="customer"))
        await db.commit()
    async with SessionFactory() as db:
        seeded = await db.scalar(select(User).where(User.id == uid))
    print(f"seeded users row : {seeded is not None} ({phone}, customer)")

    async with httpx.AsyncClient(base_url=BASE_URL, timeout=15) as client:
        health = await client.get("/health")
        print(f"health           : {health.status_code} {health.text}")

        headers = {"Authorization": f"Bearer {token}"}
        checks = [
            ("/api/v1/auth/me", None),
            ("/api/v1/customers/profile", None),
            ("/api/v1/addresses", None),
            ("/api/v1/shops/nearby", {"lat": 12.9716, "lng": 77.5946}),
        ]
        print()
        for path, params in checks:
            resp = await client.get(path, headers=headers, params=params)
            print(f"{path:32s} -> {resp.status_code}  {resp.text[:100]}")

        # And the same call with no token at all, to show the gate works.
        anon = await client.get("/api/v1/auth/me")
        print(f"\n{'(no token) /api/v1/auth/me':32s} -> {anon.status_code}  {anon.text[:100]}")


if __name__ == "__main__":
    asyncio.run(main())
