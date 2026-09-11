"""Auth router tests — /api/v1/auth/me."""

from app.domain.enums import UserRole


async def test_me_returns_user_profile(client, authenticate):
    user = authenticate(UserRole.CUSTOMER)
    response = await client.get("/api/v1/auth/me")
    assert response.status_code == 200
    body = response.json()
    assert body["phone"] == user.phone
    assert body["role"] == "customer"


async def test_me_requires_authentication(client):
    response = await client.get("/api/v1/auth/me")
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "not_authenticated"
