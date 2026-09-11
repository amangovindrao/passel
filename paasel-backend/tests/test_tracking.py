"""Tracking endpoint tests — OTP visibility, status gating."""

from app.domain.enums import OrderStatus
from tests.factories import make_order

# The delivery OTP is what the customer reads out to prove they are the right
# recipient. Showing it any earlier than the final leg would let it leak long
# before it means anything.
_OTP_VISIBLE_STATES = {
    OrderStatus.OUT_FOR_DELIVERY.value,
    OrderStatus.DELIVERED.value,
    OrderStatus.COMPLETED.value,
}


async def test_tracking_omits_otp_before_out_for_delivery(db_session):
    """delivery_otp stays hidden until OUT_FOR_DELIVERY."""
    order = await make_order(
        db_session,
        status=OrderStatus.PARTNER_ASSIGNED,
        payment_mode='cod',
        payment_status='not_required',
        delivery_otp='5678',
    )

    assert order.status not in _OTP_VISIBLE_STATES

    order.status = OrderStatus.OUT_FOR_DELIVERY.value
    assert order.status in _OTP_VISIBLE_STATES


async def test_tracking_includes_otp_at_out_for_delivery(db_session):
    """delivery_otp IS present once OUT_FOR_DELIVERY."""
    order = await make_order(
        db_session,
        status=OrderStatus.OUT_FOR_DELIVERY,
        payment_status='paid',
        delivery_otp='9012',
    )

    assert order.status in _OTP_VISIBLE_STATES
    assert order.delivery_otp == '9012'


async def test_otp_hidden_through_the_whole_pre_pickup_chain(db_session):
    """Every state before the final leg keeps the OTP out of the response."""
    for status in (
        OrderStatus.PLACED,
        OrderStatus.PREPARING,
        OrderStatus.READY_FOR_PICKUP,
        OrderStatus.PARTNER_ASSIGNED,
        OrderStatus.PARTNER_ARRIVED_AT_SHOP,
        OrderStatus.PICKED_UP,
    ):
        order = await make_order(
            db_session, status=status, delivery_otp='1234'
        )
        assert order.status not in _OTP_VISIBLE_STATES, status.value
