"""Missing-item flow tests — unavailability, customer decision, timeout."""

from uuid import uuid4

import pytest

from app.domain.enums import ItemAvailability, OrderStatus, PaymentMode
from app.models.entities import Order, OrderItem, Refund
from tests.factories import make_order, make_order_item, make_shop
from app.services.missing_item import (
    auto_proceed_on_timeout,
    handle_customer_decision,
    mark_item_unavailable,
)
from app.services.order_state_machine import clear_hooks


@pytest.fixture(autouse=True)
def _clear():
    clear_hooks()
    yield
    clear_hooks()


async def _order_with_items(db_session):
    """An order in PREPARING with two items, backed by real parent rows."""
    shop = await make_shop(db_session)
    order = await make_order(
        db_session,
        shop=shop,
        status=OrderStatus.PREPARING,
        item_total_paise=10000,
        delivery_fee_paise=2000,
        payment_mode=PaymentMode.ONLINE.value,
    )
    item_a = await make_order_item(
        db_session, order, shop=shop, price_paise=6000
    )
    item_b = await make_order_item(
        db_session, order, shop=shop, price_paise=4000
    )
    return order, item_a, item_b


async def test_mark_unavailable_transitions_to_awaiting(db_session):
    order, item_a, _ = await _order_with_items(db_session)
    await db_session.flush()

    result = await mark_item_unavailable(db_session, order, item_a.id, "Out of stock")
    assert result.status == OrderStatus.AWAITING_CUSTOMER_DECISION.value
    assert item_a.availability_status == ItemAvailability.UNAVAILABLE.value


async def test_customer_proceed_computes_revised_total(db_session):
    order, item_a, item_b = await _order_with_items(db_session)
    await db_session.flush()

    # Mark item A unavailable
    await mark_item_unavailable(db_session, order, item_a.id, "Sold out")
    await db_session.flush()

    # Customer proceeds
    result = await handle_customer_decision(db_session, order, "proceed")
    assert result.status == OrderStatus.PREPARING.value
    # Total should be only item_b price
    assert result.item_total_paise == 4000


async def test_customer_proceed_queues_refund_for_online_payment(db_session):
    order, item_a, item_b = await _order_with_items(db_session)
    await db_session.flush()

    await mark_item_unavailable(db_session, order, item_a.id, "Sold out")
    await db_session.flush()

    await handle_customer_decision(db_session, order, "proceed")
    await db_session.flush()

    # Check refund was created
    from sqlalchemy import select
    refunds = (await db_session.execute(
        select(Refund).where(Refund.order_id == order.id)
    )).scalars().all()
    assert len(refunds) == 1
    assert refunds[0].amount_paise == 6000  # item_a price
    assert refunds[0].status == "pending"


async def test_customer_hold_transitions_to_on_hold(db_session):
    order, item_a, _ = await _order_with_items(db_session)
    await db_session.flush()
    await mark_item_unavailable(db_session, order, item_a.id, "Out of stock")
    await db_session.flush()

    result = await handle_customer_decision(db_session, order, "hold")
    assert result.status == OrderStatus.ON_HOLD.value


async def test_customer_cancel_transitions_to_cancelled(db_session):
    order, item_a, _ = await _order_with_items(db_session)
    await db_session.flush()
    await mark_item_unavailable(db_session, order, item_a.id, "Out of stock")
    await db_session.flush()

    result = await handle_customer_decision(db_session, order, "cancel")
    assert result.status == OrderStatus.CANCELLED_ITEM_UNAVAILABLE.value


async def test_timeout_auto_proceeds(db_session):
    order, item_a, item_b = await _order_with_items(db_session)
    await db_session.flush()

    await mark_item_unavailable(db_session, order, item_a.id, "Sold out")
    await db_session.flush()

    # Simulate timeout
    await auto_proceed_on_timeout(db_session, order.id)

    # Reload
    await db_session.refresh(order)
    assert order.status == OrderStatus.PREPARING.value
    assert order.item_total_paise == 4000
