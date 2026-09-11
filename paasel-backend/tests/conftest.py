"""Test fixtures — mock auth, async HTTP client, DB override."""

import asyncio
import os
from datetime import UTC, datetime
from unittest.mock import AsyncMock
from uuid import UUID

import pytest
from httpx import ASGITransport, AsyncClient

# Patch env before app imports
os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://x:x@localhost:5432/x")
os.environ.setdefault("SUPABASE_URL", "https://test.supabase.co")
os.environ.setdefault("SUPABASE_JWT_SECRET", "test-secret-that-is-at-least-32-characters-long!")
os.environ.setdefault("REDIS_URL", "redis://localhost:6379/0")
os.environ.setdefault("RAZORPAY_KEY_ID", "rzp_test_000000000000")
os.environ.setdefault("RAZORPAY_KEY_SECRET", "test_secret_value")
os.environ.setdefault("GOOGLE_MAPS_API_KEY", "AIza_test_key")
os.environ.setdefault("ENVIRONMENT", "dev")

from sqlalchemy import text  # noqa: E402
from sqlalchemy.ext.asyncio import (  # noqa: E402
    AsyncSession,
    create_async_engine,
)
from sqlalchemy.pool import NullPool  # noqa: E402

from app.api.dependencies import get_current_user  # noqa: E402
from app.core.database import Base, get_db  # noqa: E402
from app.core.rate_limit import limiter  # noqa: E402

# Rate limits key on the client address, and every test shares 127.0.0.1. Left
# on, the tenth request in a file starts failing whichever test happens to make
# it — the limits are real behaviour but they are not what these tests assert.
limiter.enabled = False
from app.domain.enums import UserRole  # noqa: E402
from app.main import app as fastapi_app  # noqa: E402
from app.models.entities import User  # noqa: E402
import app.models.entities  # noqa: E402, F401 — ensure all models registered


def _make_user(role: UserRole) -> User:
    idx = list(UserRole).index(role) + 1
    return User(
        id=UUID(f"00000000-0000-0000-0000-{idx:012d}"),
        phone=f"+9199900000{idx:02d}",
        role=role.value,
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )


@pytest.fixture
def make_user():
    return _make_user


@pytest.fixture
def mock_db():
    """Override DB dependency with an AsyncMock session."""
    db = AsyncMock()

    async def override():
        yield db

    fastapi_app.dependency_overrides[get_db] = override
    yield db
    fastapi_app.dependency_overrides.pop(get_db, None)


@pytest.fixture
def authenticate(make_user):
    """Override auth dependency to return a user with the given role."""

    def _apply(role: UserRole) -> User:
        user = make_user(role)
        fastapi_app.dependency_overrides[get_current_user] = lambda: user
        return user

    return _apply


@pytest.fixture
async def client():
    async with AsyncClient(
        transport=ASGITransport(app=fastapi_app), base_url="http://test"
    ) as c:
        yield c
    fastapi_app.dependency_overrides.clear()


@pytest.fixture
async def api(db_session):
    """HTTP client wired to the real transactional test session.

    The plain `client` fixture pairs with `mock_db`, which is fine for routing
    and role checks but cannot exercise anything that touches data. This one
    points the app's get_db at the same rolled-back session the test writes
    through, so a request and the test see one consistent picture — which is
    what it takes to assert on real status codes like the offline 409.

    Call `as_user(...)` to choose who is making the request.
    """

    async def override_db():
        yield db_session

    fastapi_app.dependency_overrides[get_db] = override_db

    class Api:
        def __init__(self, http: AsyncClient) -> None:
            self._http = http

        def as_user(self, user: User) -> AsyncClient:
            fastapi_app.dependency_overrides[get_current_user] = lambda: user
            return self._http

        def anonymous(self) -> AsyncClient:
            fastapi_app.dependency_overrides.pop(get_current_user, None)
            return self._http

    async with AsyncClient(
        transport=ASGITransport(app=fastapi_app), base_url="http://test"
    ) as http:
        yield Api(http)

    fastapi_app.dependency_overrides.clear()


# ----------- SQLite-based in-process session for service/unit tests -----------
# NOTE: PostGIS functions won't work here, but pure state-machine logic does.
# Matching tests that need PostGIS use the integration marker.

_TEST_DB_URL = os.getenv(
    "TEST_DATABASE_URL",
    "postgresql+asyncpg://paasel:paasel@localhost:5433/paasel_test",
)

_db_available: bool | None = None


def _make_engine():
    """A fresh engine per test.

    Deliberately not a module-level singleton. pytest-asyncio runs each test in
    its own event loop, and an asyncpg connection is bound to the loop that
    created it — a pooled engine hands the second test a connection whose loop
    is already closed ("RuntimeError: Event loop is closed"). NullPool plus a
    per-test engine means no connection ever outlives its loop.
    """
    return create_async_engine(
        _TEST_DB_URL,
        poolclass=NullPool,
        connect_args={"timeout": 5, "command_timeout": 15},
    )


@pytest.fixture
async def db_session():
    """Provides a transactional DB session that rolls back after each test.

    Requires a running PostGIS test database:
        docker compose up -d test-db
        DATABASE_URL=<test url> alembic upgrade head

    If unavailable, tests using this fixture are skipped.
    """
    global _db_available
    if _db_available is False:
        pytest.skip("Test database not available")

    engine = _make_engine()
    try:
        if _db_available is None:
            try:
                async with asyncio.timeout(5):
                    async with engine.connect() as conn:
                        await conn.execute(text("SELECT 1"))
                _db_available = True
            except Exception:
                _db_available = False
                pytest.skip("Test database not available")

        async with engine.connect() as conn:
            txn = await conn.begin()
            session = AsyncSession(bind=conn, expire_on_commit=False)
            try:
                yield session
            finally:
                await session.close()
                await txn.rollback()
    finally:
        await engine.dispose()

