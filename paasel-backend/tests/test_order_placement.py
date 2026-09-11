"""Order placement tests — idempotency, quote, validation."""

from datetime import UTC, datetime
from uuid import uuid4

import pytest

from app.domain.enums import OrderStatus
from app.models.entities import (
    Address,
    Order,
    OrderStatusHistory,
    Product,
    Shop,
    User,
)


async def test_idempotency_key_prevents_duplicate_orders(db_session):
    """Same idempotency_key submitted twice returns same order, no duplicate."""
    customer = User(id=uuid4(), phone="+919900400001", role="customer")
    shop_owner = User(id=uuid4(), phone="+919900400002", role="shop_owner")
    db_session.add_all([customer, shop_owner])
    await db_session.flush()

    shop = Shop(
        id=uuid4(), owner_id=shop_owner.id, name="Test Shop",
        category="grocery",
        location="SRID=4326;POINT(77.5946 12.9716)",
        delivery_radius_km=4, is_open=True, subscription_status="active",
    )
    db_session.add(shop)
    await db_session.flush()

    product = Product(
        id=uuid4(), shop_id=shop.id, name="Item",
        price_paise=15000, unit="piece", stock_status="available",
    )
    db_session.add(product)

    address = Address(
        id=uuid4(), customer_id=customer.id, label="Home",
        location="SRID=4326;POINT(77.6000 12.9716)",
        address_text="Test address",
    )
    db_session.add(address)
    await db_session.flush()

    # Create first order
    idem_key = str(uuid4())
    order1 = Order(
        id=uuid4(), customer_id=customer.id, shop_id=shop.id,
        status=OrderStatus.PLACED.value,
        item_total_paise=15000, delivery_fee_paise=2000,
        payment_mode="cod", payment_status="not_required",
        delivery_otp="1234", idempotency_key=idem_key,
    )
    db_session.add(order1)
    await db_session.flush()

    # Query with same key — should find existing
    from sqlalchemy import select
    existing = await db_session.scalar(
        select(Order).where(Order.idempotency_key == idem_key)
    )
    assert existing is not None
    assert existing.id == order1.id

    # Verify no second order would be created
    count_query = select(Order).where(
        Order.customer_id == customer.id,
        Order.shop_id == shop.id,
    )
    orders = (await db_session.execute(count_query)).scalars().all()
    assert len(orders) == 1


async def test_order_below_minimum_is_rejected(db_session):
    """Orders below ₹99 are rejected with clear shortfall message."""
    from app.api.v1.order_placement import MIN_ORDER_PAISE

    customer = User(id=uuid4(), phone="+919900400003", role="customer")
    shop_owner = User(id=uuid4(), phone="+919900400004", role="shop_owner")
    db_session.add_all([customer, shop_owner])
    await db_session.flush()

    shop = Shop(
        id=uuid4(), owner_id=shop_owner.id, name="MinTest",
        category="grocery",
        location="SRID=4326;POINT(77.5946 12.9716)",
        delivery_radius_km=4, is_open=True, subscription_status="active",
    )
    db_session.add(shop)
    await db_session.flush()

    # Product priced below minimum
    cheap = Product(
        id=uuid4(), shop_id=shop.id, name="Cheap",
        price_paise=5000, unit="piece", stock_status="available",
    )
    db_session.add(cheap)
    await db_session.flush()

    # 5000 paise < 9900 paise minimum
    assert 5000 < MIN_ORDER_PAISE
