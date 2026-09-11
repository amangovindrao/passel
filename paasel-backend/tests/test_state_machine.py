"""State machine tests — transitions, guards, and rejection."""

from datetime import UTC, datetime
from uuid import uuid4

import pytest

from app.domain.enums import OrderStatus
from app.models.entities import (
    DeliveryAssignment,
    Order,
    OrderPhoto,
    OrderStatusHistory,
)
from tests.factories import make_order, make_partner
from app.services.order_state_machine import (
    ALLOWED_TRANSITIONS,
    clear_hooks,
    transition,
)


@pytest.fixture(autouse=True)
def _clear():
    clear_hooks()
    yield
    clear_hooks()


async def _order(db_session, status: OrderStatus, **kwargs) -> Order:
    """An order with real customer and shop rows behind it."""
    return await make_order(db_session, status=status, **kwargs)


async def test_valid_transition_placed_to_accepted(db_session):
    # Paid, because an unpaid online order is correctly refused at this step —
    # that guard has its own test.
    order = await _order(
        db_session, OrderStatus.PLACED, payment_status='paid'
    )

    result = await transition(db_session, order, OrderStatus.ACCEPTED_BY_SHOP)
    assert result.status == OrderStatus.ACCEPTED_BY_SHOP.value

    # Check history written
    history = (await db_session.execute(
        OrderStatusHistory.__table__.select().where(
            OrderStatusHistory.order_id == order.id
        )
    )).all()
    assert len(history) == 1
    assert history[0].status == OrderStatus.ACCEPTED_BY_SHOP.value


async def test_invalid_transition_raises_409(db_session):
    order = await _order(db_session, OrderStatus.PLACED)

    from app.core.errors import AppError
    with pytest.raises(AppError) as exc_info:
        await transition(db_session, order, OrderStatus.DELIVERED)
    assert exc_info.value.status_code == 409
    assert "PLACED" in exc_info.value.message
    assert "DELIVERED" in exc_info.value.message


async def test_guard_ready_for_pickup_requires_packing_photo(db_session):
    order = await _order(db_session, OrderStatus.PREPARING)

    from app.core.errors import AppError
    with pytest.raises(AppError) as exc_info:
        await transition(db_session, order, OrderStatus.READY_FOR_PICKUP)
    assert exc_info.value.status_code == 422
    assert "packing photo" in exc_info.value.message.lower()


async def test_guard_ready_for_pickup_passes_with_photo(db_session):
    order = await _order(db_session, OrderStatus.PREPARING)

    db_session.add(OrderPhoto(
        order_id=order.id, captured_by="shop", stage="packing",
        photo_url="https://storage.example.com/photo.jpg",
    ))
    await db_session.flush()

    result = await transition(db_session, order, OrderStatus.READY_FOR_PICKUP)
    assert result.status == OrderStatus.READY_FOR_PICKUP.value


async def test_guard_picked_up_requires_photo_and_code(db_session):
    order = await _order(db_session, OrderStatus.PARTNER_ARRIVED_AT_SHOP)

    from app.core.errors import AppError

    # No photo, no code
    with pytest.raises(AppError) as exc_info:
        await transition(db_session, order, OrderStatus.PICKED_UP)
    assert "photo" in exc_info.value.message.lower()

    # Add photo but no code
    db_session.add(OrderPhoto(
        order_id=order.id, captured_by="delivery_partner", stage="pickup",
        photo_url="https://storage.example.com/pickup.jpg",
    ))
    await db_session.flush()

    with pytest.raises(AppError) as exc_info:
        await transition(db_session, order, OrderStatus.PICKED_UP)
    assert "code" in exc_info.value.message.lower()

    # Add assignment with pickup code
    partner = await make_partner(db_session)
    db_session.add(DeliveryAssignment(
        order_id=order.id, partner_id=partner.id, trip_id=uuid4(),
        pickup_code="5678",
    ))
    await db_session.flush()

    # Wrong code
    with pytest.raises(AppError):
        await transition(db_session, order, OrderStatus.PICKED_UP, pickup_code="0000")

    # Correct code
    result = await transition(db_session, order, OrderStatus.PICKED_UP, pickup_code="5678")
    assert result.status == OrderStatus.PICKED_UP.value


async def test_guard_delivered_requires_photo_and_otp(db_session):
    order = await _order(db_session, OrderStatus.OUT_FOR_DELIVERY)

    from app.core.errors import AppError

    # No photo
    with pytest.raises(AppError):
        await transition(db_session, order, OrderStatus.DELIVERED)

    db_session.add(OrderPhoto(
        order_id=order.id, captured_by="delivery_partner", stage="delivery",
        photo_url="https://storage.example.com/delivery.jpg",
    ))
    await db_session.flush()

    # No OTP
    with pytest.raises(AppError):
        await transition(db_session, order, OrderStatus.DELIVERED)

    # Wrong OTP
    with pytest.raises(AppError):
        await transition(db_session, order, OrderStatus.DELIVERED, otp="0000")

    # Correct OTP
    result = await transition(db_session, order, OrderStatus.DELIVERED, otp="1234")
    assert result.status == OrderStatus.DELIVERED.value


async def test_no_cancellation_after_pickup(db_session):
    order = await _order(db_session, OrderStatus.PICKED_UP)

    from app.core.errors import AppError
    with pytest.raises(AppError) as exc_info:
        await transition(db_session, order, OrderStatus.CANCELLED_BY_CUSTOMER)
    assert exc_info.value.status_code == 422
    assert "cancel" in exc_info.value.message.lower()


async def test_cancellation_allowed_from_preparing(db_session):
    order = await _order(db_session, OrderStatus.PREPARING)

    result = await transition(db_session, order, OrderStatus.CANCELLED_BY_CUSTOMER)
    assert result.status == OrderStatus.CANCELLED_BY_CUSTOMER.value
