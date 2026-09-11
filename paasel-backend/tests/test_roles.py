"""Role-gating matrix tests — verifies every router's access control."""

import pytest

from app.domain.enums import UserRole

# Maps each role to the router paths it should access
ROLE_TO_PATHS: dict[UserRole, list[str]] = {
    UserRole.CUSTOMER: ["/api/v1/orders/_role-check", "/api/v1/payments/_role-check"],
    UserRole.SHOP_OWNER: [
        "/api/v1/shops/_role-check",
        "/api/v1/products/_role-check",
        "/api/v1/subscriptions/_role-check",
    ],
    UserRole.DELIVERY_PARTNER: ["/api/v1/delivery/_role-check"],
    UserRole.ADMIN: ["/api/v1/admin/_role-check"],
}

# Wallets allow shop_owner OR delivery_partner
WALLET_PATH = "/api/v1/wallets/_role-check"
WALLET_ROLES = {UserRole.SHOP_OWNER, UserRole.DELIVERY_PARTNER}

ALL_PATHS = [p for paths in ROLE_TO_PATHS.values() for p in paths]


@pytest.mark.parametrize("role", list(UserRole))
@pytest.mark.parametrize(
    "path",
    ALL_PATHS + [WALLET_PATH],
)
async def test_role_policy(client, authenticate, role, path):
    authenticate(role)
    response = await client.get(path)

    if path == WALLET_PATH:
        expected = 200 if role in WALLET_ROLES else 403
    elif path in ROLE_TO_PATHS.get(role, []):
        expected = 200
    else:
        expected = 403

    assert response.status_code == expected, (
        f"{role.value} on {path}: expected {expected}, got {response.status_code}"
    )


@pytest.mark.parametrize("path", ALL_PATHS + [WALLET_PATH])
async def test_unauthenticated_gets_401(client, path):
    response = await client.get(path)
    assert response.status_code == 401


async def test_customer_cannot_access_shop_route(client, authenticate):
    """Explicit spec requirement: customer hitting shop-owner endpoint gets 403."""
    authenticate(UserRole.CUSTOMER)
    response = await client.get("/api/v1/shops/_role-check")
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "forbidden"
