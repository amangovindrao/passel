"""End-to-end order flow test — PLACED to DELIVERED with all guards.

This test proves a customer can walk an order through the full lifecycle
via direct service calls, including a missing-item detour.
"""

from datetime import UTC, datetime
from uuid import uuid4

import pytest

from app.domain.enums import ItemAvailability, OrderStatus, PaymentMode
from app.models.entities import (
    DeliveryAssignment,
    DeliveryPartnerProfile,
    LiveLocation,
    Order,
    OrderItem,
    OrderPhoto,
    OrderStatusHistory,
    Shop,
    User,
)
from app.services.missing_item import handle_customer_decision, mark_item_unavailable
from app.services.order_state_machine import clear_hooks, transition
from tests.factories import make_product


@pytest.fixture(autouse=True)
def _clear():
    clear_hooks()
    yield
    clear_hooks()


async def test_full_order_lifecycle(db_session):
    """Walk an order from PLACED to COMPLETED with all guards satisfied."""

    # --- Setup ---
    customer = User(id=uuid4(), phone="+919900000001", role="customer")
    shop_owner = User(id=uuid4(), phone="+919900000002", role="shop_owner")
    partner_user = User(id=uuid4(), phone="+919900000003", role="delivery_partner")
    db_session.add_all([customer, shop_owner, partner_user])
    await db_session.flush()

    shop = Shop(
        id=uuid4(), owner_id=shop_owner.id, name="E2E Shop",
        category="grocery",
        location="SRID=4326;POINT(77.5946 12.9716)",
        delivery_radius_km=4, is_open=True, subscription_status="active",
    )
    db_session.add(shop)

    db_session.add(DeliveryPartnerProfile(
        user_id=partner_user.id, name="Test Partner",
        vehicle_type="bike", is_online=True,
    ))
    db_session.add(LiveLocation(
        partner_id=partner_user.id,
        location="SRID=4326;POINT(77.5960 12.9716)",
        updated_at=datetime.now(UTC),
    ))
    await db_session.flush()

    product = await make_product(db_session, shop, price_paise=25000)

    order = Order(
        id=uuid4(), customer_id=customer.id, shop_id=shop.id,
        status=OrderStatus.PLACED.value,
        item_total_paise=50000, delivery_fee_paise=3000,
        payment_mode=PaymentMode.ONLINE.value,
        # Paid: an online order is correctly refused at shop acceptance until
        # the money has landed, and that guard has its own test.
        payment_status="paid",
        delivery_otp="7890",
    )
    item = OrderItem(
        id=uuid4(), order_id=order.id, product_id=product.id,
        qty=2, price_at_order_time_paise=25000,
        availability_status=ItemAvailability.AVAILABLE.value,
    )
    db_session.add_all([order, item])
    await db_session.flush()

    # --- PLACED -> ACCEPTED_BY_SHOP -> PREPARING ---
    order = await transition(db_session, order, OrderStatus.ACCEPTED_BY_SHOP)
    order = await transition(db_session, order, OrderStatus.PREPARING)
    assert order.status == OrderStatus.PREPARING.value

    # --- PREPARING -> READY_FOR_PICKUP (requires packing photo) ---
    db_session.add(OrderPhoto(
        order_id=order.id, captured_by="shop", stage="packing",
        photo_url="https://storage.example.com/packing1.jpg",
    ))
    await db_session.flush()
    order = await transition(db_session, order, OrderStatus.READY_FOR_PICKUP)
    assert order.status == OrderStatus.READY_FOR_PICKUP.value

    # --- READY_FOR_PICKUP -> PARTNER_ASSIGNED ---
    assignment = DeliveryAssignment(
        order_id=order.id, partner_id=partner_user.id,
        trip_id=uuid4(), pickup_code="4321",
        accepted_at=datetime.now(UTC),
    )
    db_session.add(assignment)
    await db_session.flush()
    order = await transition(db_session, order, OrderStatus.PARTNER_ASSIGNED)
    assert order.status == OrderStatus.PARTNER_ASSIGNED.value

    # --- PARTNER_ASSIGNED -> PARTNER_ARRIVED_AT_SHOP ---
    order = await transition(db_session, order, OrderStatus.PARTNER_ARRIVED_AT_SHOP)
    assert order.status == OrderStatus.PARTNER_ARRIVED_AT_SHOP.value

    # --- PARTNER_ARRIVED_AT_SHOP -> PICKED_UP (requires pickup photo + code) ---
    db_session.add(OrderPhoto(
        order_id=order.id, captured_by="delivery_partner", stage="pickup",
        photo_url="https://storage.example.com/pickup1.jpg",
    ))
    await db_session.flush()
    order = await transition(
        db_session, order, OrderStatus.PICKED_UP, pickup_code="4321"
    )
    assert order.status == OrderStatus.PICKED_UP.value

    # --- PICKED_UP -> OUT_FOR_DELIVERY ---
    order = await transition(db_session, order, OrderStatus.OUT_FOR_DELIVERY)
    assert order.status == OrderStatus.OUT_FOR_DELIVERY.value

    # --- OUT_FOR_DELIVERY -> DELIVERED (requires delivery photo + OTP) ---
    db_session.add(OrderPhoto(
        order_id=order.id, captured_by="delivery_partner", stage="delivery",
        photo_url="https://storage.example.com/delivery1.jpg",
    ))
    await db_session.flush()
    order = await transition(db_session, order, OrderStatus.DELIVERED, otp="7890")
    assert order.status == OrderStatus.DELIVERED.value

    # --- DELIVERED -> COMPLETED ---
    order = await transition(db_session, order, OrderStatus.COMPLETED)
    assert order.status == OrderStatus.COMPLETED.value

    # --- Verify full history ---
    from sqlalchemy import select, func
    count = await db_session.scalar(
        select(func.count()).select_from(OrderStatusHistory)
        .where(OrderStatusHistory.order_id == order.id)
    )
    # ACCEPTED_BY_SHOP, PREPARING, READY_FOR_PICKUP, PARTNER_ASSIGNED,
    # PARTNER_ARRIVED_AT_SHOP, PICKED_UP, OUT_FOR_DELIVERY, DELIVERED, COMPLETED = 9
    assert count == 9


async def test_missing_item_detour_then_complete(db_session):
    """Order with missing item: transitions through AWAITING_CUSTOMER_DECISION
    and back to PREPARING, then completes normally."""

    customer = User(id=uuid4(), phone="+919900000011", role="customer")
    shop_owner = User(id=uuid4(), phone="+919900000012", role="shop_owner")
    partner_user = User(id=uuid4(), phone="+919900000013", role="delivery_partner")
    db_session.add_all([customer, shop_owner, partner_user])
    await db_session.flush()

    shop = Shop(
        id=uuid4(), owner_id=shop_owner.id, name="Detour Shop",
        category="grocery",
        location="SRID=4326;POINT(77.5946 12.9716)",
        delivery_radius_km=4, is_open=True, subscription_status="active",
    )
    db_session.add(shop)
    await db_session.flush()

    product_a = await make_product(db_session, shop, price_paise=6000)
    product_b = await make_product(db_session, shop, price_paise=4000)

    order = Order(
        id=uuid4(), customer_id=customer.id, shop_id=shop.id,
        status=OrderStatus.PLACED.value,
        item_total_paise=10000, delivery_fee_paise=2000,
        payment_mode=PaymentMode.ONLINE.value,
        payment_status="paid",
        delivery_otp="5555",
    )
    item_a = OrderItem(
        id=uuid4(), order_id=order.id, product_id=product_a.id,
        qty=1, price_at_order_time_paise=6000,
    )
    item_b = OrderItem(
        id=uuid4(), order_id=order.id, product_id=product_b.id,
        qty=1, price_at_order_time_paise=4000,
    )
    db_session.add_all([order, item_a, item_b])
    await db_session.flush()

    # Accept and start preparing
    order = await transition(db_session, order, OrderStatus.ACCEPTED_BY_SHOP)
    order = await transition(db_session, order, OrderStatus.PREPARING)

    # Shop marks item_a unavailable
    order = await mark_item_unavailable(db_session, order, item_a.id, "Sold out")
    assert order.status == OrderStatus.AWAITING_CUSTOMER_DECISION.value

    # Customer proceeds
    order = await handle_customer_decision(db_session, order, "proceed")
    assert order.status == OrderStatus.PREPARING.value
    assert order.item_total_paise == 4000  # Only item_b

    # Continue to completion
    db_session.add(OrderPhoto(
        order_id=order.id, captured_by="shop", stage="packing",
        photo_url="https://storage.example.com/packing.jpg",
    ))
    await db_session.flush()
    order = await transition(db_session, order, OrderStatus.READY_FOR_PICKUP)

    db_session.add(DeliveryPartnerProfile(
        user_id=partner_user.id, name="P",
        vehicle_type="bike", is_online=True,
    ))
    db_session.add(LiveLocation(
        partner_id=partner_user.id,
        location="SRID=4326;POINT(77.5960 12.9716)",
        updated_at=datetime.now(UTC),
    ))
    assignment = DeliveryAssignment(
        order_id=order.id, partner_id=partner_user.id,
        trip_id=uuid4(), pickup_code="9999",
        accepted_at=datetime.now(UTC),
    )
    db_session.add(assignment)
    await db_session.flush()

    order = await transition(db_session, order, OrderStatus.PARTNER_ASSIGNED)
    order = await transition(db_session, order, OrderStatus.PARTNER_ARRIVED_AT_SHOP)

    db_session.add(OrderPhoto(
        order_id=order.id, captured_by="delivery_partner", stage="pickup",
        photo_url="https://storage.example.com/pickup.jpg",
    ))
    await db_session.flush()
    order = await transition(db_session, order, OrderStatus.PICKED_UP, pickup_code="9999")
    order = await transition(db_session, order, OrderStatus.OUT_FOR_DELIVERY)

    db_session.add(OrderPhoto(
        order_id=order.id, captured_by="delivery_partner", stage="delivery",
        photo_url="https://storage.example.com/delivery.jpg",
    ))
    await db_session.flush()
    order = await transition(db_session, order, OrderStatus.DELIVERED, otp="5555")
    order = await transition(db_session, order, OrderStatus.COMPLETED)
    assert order.status == OrderStatus.COMPLETED.value
