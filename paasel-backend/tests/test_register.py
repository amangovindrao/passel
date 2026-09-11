"""Registration — turning a Supabase identity into an account here.

Without this every other endpoint 401s for a genuinely logged-in user, so these
tests go over HTTP with a real signed token rather than a stubbed dependency.
"""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import jwt
import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.core.config import settings
from app.core.database import get_db
from app.domain.enums import UserRole
from app.main import app as fastapi_app
from app.models.entities import (
    CustomerProfile,
    DeliveryPartnerProfile,
    ShopOwnerProfile,
    User,
)

REGISTER = "/api/v1/auth/register"


def token_for(user_id, phone: str | None = "+919900000001") -> str:
    """A token shaped exactly like the one Supabase issues after phone OTP."""
    now = datetime.now(UTC)
    claims = {
        "sub": str(user_id),
        "aud": "authenticated",
        "iss": settings.supabase_issuer,
        "role": "authenticated",
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(hours=1)).timestamp()),
    }
    if phone is not None:
        claims["phone"] = phone
    return jwt.encode(
        claims, settings.supabase_jwt_secret, algorithm="HS256"
    )


@pytest.fixture
async def http(db_session):
    """Real HTTP client on the test session, with auth left to the token.

    Deliberately does not override get_current_user — registration is exactly
    the path where that dependency must not be short-circuited.
    """

    async def override_db():
        yield db_session

    fastapi_app.dependency_overrides[get_db] = override_db
    async with AsyncClient(
        transport=ASGITransport(app=fastapi_app), base_url="http://test"
    ) as client:
        yield client
    fastapi_app.dependency_overrides.clear()


def auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


# --- Happy paths, one per role ---


@pytest.mark.parametrize(
    ("role", "profile_model"),
    [
        (UserRole.CUSTOMER.value, CustomerProfile),
        (UserRole.SHOP_OWNER.value, ShopOwnerProfile),
        (UserRole.DELIVERY_PARTNER.value, DeliveryPartnerProfile),
    ],
)
async def test_register_creates_user_and_profile(
    http, db_session, role, profile_model
):
    uid = uuid4()
    phone = f"+9199{uuid4().int % 10**8:08d}"

    resp = await http.post(
        REGISTER,
        json={"name": "Test Person", "role": role},
        headers=auth(token_for(uid, phone)),
    )

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body == {"user_id": str(uid), "role": role, "created": True}

    user = await db_session.scalar(select(User).where(User.id == uid))
    assert user is not None
    assert user.role == role
    assert user.phone == phone

    profile = await db_session.scalar(
        select(profile_model).where(profile_model.user_id == uid)
    )
    assert profile is not None, "the role's profile row must exist too"
    assert profile.name == "Test Person"


async def test_registered_user_can_immediately_use_the_api(http, db_session):
    """The point of the whole endpoint: /auth/me works straight afterwards."""
    uid = uuid4()
    token = token_for(uid, f"+9199{uuid4().int % 10**8:08d}")

    before = await http.get("/api/v1/auth/me", headers=auth(token))
    assert before.status_code == 401
    assert before.json()["error"]["code"] == "registration_required"

    await http.post(
        REGISTER,
        json={"name": "Ravi", "role": UserRole.CUSTOMER.value},
        headers=auth(token),
    )

    after = await http.get("/api/v1/auth/me", headers=auth(token))
    assert after.status_code == 200
    assert after.json()["role"] == UserRole.CUSTOMER.value


# --- Idempotency ---


async def test_register_is_idempotent(http, db_session):
    """Apps retry on every launch, so a repeat must be a no-op."""
    uid = uuid4()
    token = token_for(uid, f"+9199{uuid4().int % 10**8:08d}")
    payload = {"name": "Ravi", "role": UserRole.CUSTOMER.value}

    first = await http.post(REGISTER, json=payload, headers=auth(token))
    second = await http.post(REGISTER, json=payload, headers=auth(token))

    assert first.json()["created"] is True
    assert second.json()["created"] is False
    assert second.json()["role"] == UserRole.CUSTOMER.value

    users = (
        await db_session.execute(select(User).where(User.id == uid))
    ).scalars().all()
    assert len(users) == 1
    profiles = (
        await db_session.execute(
            select(CustomerProfile).where(CustomerProfile.user_id == uid)
        )
    ).scalars().all()
    assert len(profiles) == 1, "no duplicate profile on retry"


async def test_repeat_registration_cannot_change_role(http, db_session):
    """A second call claiming a different role must not escalate anything."""
    uid = uuid4()
    token = token_for(uid, f"+9199{uuid4().int % 10**8:08d}")

    await http.post(
        REGISTER,
        json={"name": "Ravi", "role": UserRole.CUSTOMER.value},
        headers=auth(token),
    )
    resp = await http.post(
        REGISTER,
        json={"name": "Ravi", "role": UserRole.SHOP_OWNER.value},
        headers=auth(token),
    )

    assert resp.json()["role"] == UserRole.CUSTOMER.value
    user = await db_session.scalar(select(User).where(User.id == uid))
    assert user.role == UserRole.CUSTOMER.value


# --- Refusals ---


async def test_cannot_self_assign_admin(http, db_session):
    uid = uuid4()

    resp = await http.post(
        REGISTER,
        json={"name": "Sneaky", "role": UserRole.ADMIN.value},
        headers=auth(token_for(uid)),
    )

    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "invalid_role"
    assert await db_session.scalar(select(User).where(User.id == uid)) is None


async def test_unknown_role_is_refused(http):
    resp = await http.post(
        REGISTER,
        json={"name": "Someone", "role": "superuser"},
        headers=auth(token_for(uuid4())),
    )
    assert resp.status_code == 422


async def test_register_requires_a_token(http):
    resp = await http.post(
        REGISTER, json={"name": "Someone", "role": "customer"}
    )
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "not_authenticated"


async def test_register_rejects_a_forged_token(http):
    forged = jwt.encode(
        {
            "sub": str(uuid4()),
            "aud": "authenticated",
            "iss": settings.supabase_issuer,
            "phone": "+919900000009",
            "exp": int(
                (datetime.now(UTC) + timedelta(hours=1)).timestamp()
            ),
        },
        "not-the-real-secret",
        algorithm="HS256",
    )

    resp = await http.post(
        REGISTER,
        json={"name": "Someone", "role": "customer"},
        headers=auth(forged),
    )

    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "invalid_token"


async def test_phone_comes_from_the_token_not_the_body(http, db_session):
    """A client must not be able to claim someone else's number."""
    uid = uuid4()
    real_phone = f"+9199{uuid4().int % 10**8:08d}"

    await http.post(
        REGISTER,
        json={
            "name": "Ravi",
            "role": UserRole.CUSTOMER.value,
            # Ignored: not part of the schema, and the token is authoritative.
            "phone": "+919999999999",
        },
        headers=auth(token_for(uid, real_phone)),
    )

    user = await db_session.scalar(select(User).where(User.id == uid))
    assert user.phone == real_phone


async def test_token_without_a_phone_is_refused(http):
    resp = await http.post(
        REGISTER,
        json={"name": "Ravi", "role": UserRole.CUSTOMER.value},
        headers=auth(token_for(uuid4(), phone=None)),
    )

    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "phone_required"


async def test_a_number_cannot_be_registered_twice(http, db_session):
    """Same phone, different Supabase identity — refuse rather than orphan."""
    phone = f"+9199{uuid4().int % 10**8:08d}"

    first = await http.post(
        REGISTER,
        json={"name": "First", "role": UserRole.CUSTOMER.value},
        headers=auth(token_for(uuid4(), phone)),
    )
    assert first.status_code == 200

    second = await http.post(
        REGISTER,
        json={"name": "Second", "role": UserRole.CUSTOMER.value},
        headers=auth(token_for(uuid4(), phone)),
    )

    assert second.status_code == 409
    assert second.json()["error"]["code"] == "phone_in_use"


async def test_name_must_be_meaningful(http):
    resp = await http.post(
        REGISTER,
        json={"name": "R", "role": UserRole.CUSTOMER.value},
        headers=auth(token_for(uuid4())),
    )
    assert resp.status_code == 422


# --- registration-status ---


async def test_registration_status_before_and_after(http, db_session):
    uid = uuid4()
    token = token_for(uid, f"+9199{uuid4().int % 10**8:08d}")

    before = await http.get(
        "/api/v1/auth/registration-status", headers=auth(token)
    )
    assert before.json() == {"registered": False, "role": None}

    await http.post(
        REGISTER,
        json={"name": "Ravi", "role": UserRole.DELIVERY_PARTNER.value},
        headers=auth(token),
    )

    after = await http.get(
        "/api/v1/auth/registration-status", headers=auth(token)
    )
    assert after.json() == {
        "registered": True,
        "role": UserRole.DELIVERY_PARTNER.value,
    }


async def test_rider_can_reach_their_own_profile_after_registering(
    http, db_session
):
    """A registered rider lands on a real profile, not a 404."""
    uid = uuid4()
    token = token_for(uid, f"+9199{uuid4().int % 10**8:08d}")

    await http.post(
        REGISTER,
        json={"name": "Ravi", "role": UserRole.DELIVERY_PARTNER.value},
        headers=auth(token),
    )

    resp = await http.get(
        "/api/v1/delivery-partners/me", headers=auth(token)
    )

    assert resp.status_code == 200
    body = resp.json()
    assert body["exists"] is True
    assert body["name"] == "Ravi"
    assert body["kyc_status"] == "pending"
    assert body["is_online"] is False
