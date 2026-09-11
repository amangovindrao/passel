"""Payment tests — webhook verification, idempotency, settlement."""

import hashlib
import hmac
import json
from datetime import UTC, datetime
from uuid import uuid4

import pytest

from app.core.config import settings
from app.domain.enums import OrderStatus, PaymentMode, WalletTxnType
from app.models.entities import (
    DeliveryAssignment,
    Order,
    Payment,
    Shop,
    User,
    Wallet,
    WalletTransaction,
)
from app.services.payment_service import (
    clear_processed_events,
    handle_payment_captured,
    is_event_processed,
    mark_event_processed,
)
from app.services.wallet_service import (
    compute_unsettled_balance,
    get_or_create_wallet,
    settle_on_delivery,
)
from app.domain.enums import WalletOwnerType


@pytest.fixture(autouse=True)
def _clear_events():
    clear_processed_events()
    yield
    clear_processed_events()


async def test_webhook_signature_verification(client, mock_db):
    """Valid signature passes, tampered payload is rejected."""
    body = json.dumps({"event": "payment.captured", "id": "evt_1"}).encode()
    secret = settings.razorpay_key_secret.encode()
    valid_sig = hmac.new(secret, body, hashlib.sha256).hexdigest()

    # Valid signature
    response = await client.post(
        "/api/v1/payments/webhooks/razorpay",
        content=body,
        headers={
            "X-Razorpay-Signature": valid_sig,
            "Content-Type": "application/json",
        },
    )
    assert response.status_code == 200

    # Tampered payload
    tampered = body + b"TAMPERED"
    response = await client.post(
        "/api/v1/payments/webhooks/razorpay",
        content=tampered,
        headers={
            "X-Razorpay-Signature": valid_sig,
            "Content-Type": "application/json",
        },
    )
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "invalid_signature"


async def test_webhook_idempotency(client, mock_db):
    """Same event sent twice results in single processing."""
    event_id = "evt_idempotent_123"
    body = json.dumps({
        "event": "payment.captured",
        "id": event_id,
        "payload": {"payment": {"entity": {
            "id": "pay_xxx",
            "order_id": "order_xxx",
            "amount": 50000,
            "notes": {"paasel_order_id": str(uuid4())},
        }}},
    }).encode()
    secret = settings.razorpay_key_secret.encode()
    sig = hmac.new(secret, body, hashlib.sha256).hexdigest()

    # First call
    r1 = await client.post(
        "/api/v1/payments/webhooks/razorpay",
        content=body,
        headers={"X-Razorpay-Signature": sig, "Content-Type": "application/json"},
    )
    assert r1.status_code == 200
    assert r1.json()["status"] == "processed"

    # Second call — idempotent
    r2 = await client.post(
        "/api/v1/payments/webhooks/razorpay",
        content=body,
        headers={"X-Razorpay-Signature": sig, "Content-Type": "application/json"},
    )
    assert r2.status_code == 200
    assert r2.json()["status"] == "already_processed"


async def test_cod_settlement_creates_correct_wallet_entries(db_session):
    """COD order at DELIVERED: shop gets earning credit, partner gets
    delivery_fee credit + cod_debit for item_total."""
    from app.services.order_state_machine import clear_hooks
    clear_hooks()

    # Setup
    customer = User(id=uuid4(), phone="+919900100001", role="customer")
    shop_owner = User(id=uuid4(), phone="+919900100002", role="shop_owner")
    partner = User(id=uuid4(), phone="+919900100003", role="delivery_partner")
    db_session.add_all([customer, shop_owner, partner])
    await db_session.flush()

    shop = Shop(
        id=uuid4(), owner_id=shop_owner.id, name="COD Shop",
        category="grocery", location="SRID=4326;POINT(77.5946 12.9716)",
        delivery_radius_km=4, is_open=True, subscription_status="active",
    )
    db_session.add(shop)
    await db_session.flush()

    order = Order(
        id=uuid4(), customer_id=customer.id, shop_id=shop.id,
        status=OrderStatus.DELIVERED.value,
        item_total_paise=50000, delivery_fee_paise=3000,
        payment_mode=PaymentMode.COD.value,
        payment_status="not_applicable",
    )
    db_session.add(order)
    await db_session.flush()

    db_session.add(DeliveryAssignment(
        order_id=order.id, partner_id=partner.id,
        trip_id=uuid4(), pickup_code="1234",
        accepted_at=datetime.now(UTC),
    ))
    await db_session.flush()

    # Execute settlement
    await settle_on_delivery(db_session, order)
    await db_session.flush()

    # Verify shop wallet
    shop_wallet = await get_or_create_wallet(
        db_session, shop_owner.id, WalletOwnerType.SHOP
    )
    shop_balance = await compute_unsettled_balance(db_session, shop_wallet.id)
    assert shop_balance == 50000  # Earning credit, unsettled

    # Verify partner wallet
    partner_wallet = await get_or_create_wallet(
        db_session, partner.id, WalletOwnerType.DELIVERY_PARTNER
    )
    partner_balance = await compute_unsettled_balance(db_session, partner_wallet.id)
    # delivery_fee (3000) + cod_debit (-50000) = -47000
    # But delivery_fee is also manual_payout for COD
    # Actually: earning +3000, cod_debit -50000 = -47000
    assert partner_balance == 3000 + (-50000)  # = -47000


async def test_online_settlement_marks_route_auto(db_session):
    """Online order settlement marks transactions as route_auto with settled_at."""
    from app.services.order_state_machine import clear_hooks
    clear_hooks()

    customer = User(id=uuid4(), phone="+919900200001", role="customer")
    shop_owner = User(id=uuid4(), phone="+919900200002", role="shop_owner")
    partner = User(id=uuid4(), phone="+919900200003", role="delivery_partner")
    db_session.add_all([customer, shop_owner, partner])
    await db_session.flush()

    shop = Shop(
        id=uuid4(), owner_id=shop_owner.id, name="Online Shop",
        category="grocery", location="SRID=4326;POINT(77.5946 12.9716)",
        delivery_radius_km=4, is_open=True, subscription_status="active",
    )
    db_session.add(shop)
    await db_session.flush()

    order = Order(
        id=uuid4(), customer_id=customer.id, shop_id=shop.id,
        status=OrderStatus.DELIVERED.value,
        item_total_paise=40000, delivery_fee_paise=2500,
        payment_mode=PaymentMode.ONLINE.value,
        payment_status="paid",
    )
    db_session.add(order)
    await db_session.flush()

    db_session.add(DeliveryAssignment(
        order_id=order.id, partner_id=partner.id,
        trip_id=uuid4(), pickup_code="5678",
        accepted_at=datetime.now(UTC),
    ))
    await db_session.flush()

    await settle_on_delivery(db_session, order)
    await db_session.flush()

    # Online: both should be route_auto with settled_at set
    from sqlalchemy import select
    shop_wallet = await get_or_create_wallet(
        db_session, shop_owner.id, WalletOwnerType.SHOP
    )
    txns = (await db_session.execute(
        select(WalletTransaction).where(WalletTransaction.wallet_id == shop_wallet.id)
    )).scalars().all()
    assert len(txns) == 1
    assert txns[0].settlement_channel == "route_auto"
    assert txns[0].settled_at is not None
    assert txns[0].amount_paise == 40000
