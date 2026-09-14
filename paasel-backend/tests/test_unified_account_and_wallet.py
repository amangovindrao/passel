"""Tests for Unified Customer/Rider Account & Shared Transaction Ledger Wallet."""

from datetime import UTC, datetime
from uuid import uuid4

import pytest
from app.domain.enums import UserRole, WalletOwnerType, WalletTxnType
from app.models.entities import CustomerProfile, DeliveryPartnerProfile, Order, User, Wallet, WalletTransaction


def test_user_multi_role_logic():
    """Verify that a User can hold multiple roles simultaneously and has_role correctly detects them."""
    user = User(
        id=uuid4(),
        phone="+919999999999",
        role=UserRole.CUSTOMER.value,
        roles=[UserRole.CUSTOMER.value],
    )
    assert user.has_role(UserRole.CUSTOMER)
    assert not user.has_role(UserRole.DELIVERY_PARTNER)
    assert user.all_roles == ["customer"]

    # Append delivery_partner role
    user.roles = ["customer", "delivery_partner"]
    assert user.has_role(UserRole.CUSTOMER)
    assert user.has_role(UserRole.DELIVERY_PARTNER)
    assert set(user.all_roles) == {"customer", "delivery_partner"}


def test_wallet_transaction_ledger_entity():
    """Verify WalletTransaction entity structure, directions, and idempotency key."""
    wallet_id = uuid4()
    order_id = uuid4()
    txn = WalletTransaction(
        id=uuid4(),
        wallet_id=wallet_id,
        type=WalletTxnType.RIDER_EARNING.value,
        amount_paise=2500,
        direction="CREDIT",
        status="COMPLETED",
        order_id=order_id,
        idempotency_key=f"earn_{order_id}",
        description="Delivery earning for order",
    )
    assert txn.direction == "CREDIT"
    assert txn.status == "COMPLETED"
    assert txn.amount_paise == 2500
    assert txn.idempotency_key == f"earn_{order_id}"


def test_order_multishop_and_wallet_fields():
    """Verify Order entity has parent_order_id, wallet_amount_used_paise, and is_multi_shop."""
    order = Order(
        id=uuid4(),
        customer_id=uuid4(),
        shop_id=uuid4(),
        status="PLACED",
        item_total_paise=15000,
        delivery_fee_paise=2500,
        payment_mode="wallet",
        wallet_amount_used_paise=17500,
        is_multi_shop=True,
    )
    assert order.is_multi_shop is True
    assert order.wallet_amount_used_paise == 17500
    assert order.payment_mode == "wallet"
