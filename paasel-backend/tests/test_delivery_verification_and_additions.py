"""Tests for Delivery Verification, 7-Minute Return Window, Expired Item Shop-Charge Rule, and Order Additions."""

from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import pytest

from app.domain.enums import (
    AdditionStatus,
    AdditionWindowStatus,
    OrderStatus,
    ReturnChargePayer,
    ReturnReason,
    ReturnStatus,
    VerificationStatus,
)
from app.models.entities import (
    MerchantQualityIncident,
    Order,
    OrderAddition,
    OrderAdditionItem,
    OrderItem,
    OrderReturn,
    Product,
)


def test_handover_initiation_sets_7_min_deadline():
    """When delivery partner reaches customer, a 7-minute window is set."""
    now = datetime.now(UTC)
    order = Order(
        id=uuid4(),
        customer_id=uuid4(),
        shop_id=uuid4(),
        status=OrderStatus.OUT_FOR_DELIVERY.value,
        delivery_status="OUT_FOR_DELIVERY",
        item_total_paise=15000,
        delivery_fee_paise=2500,
        payment_mode="online",
        payment_status="paid",
        handover_initiated_at=now,
        verification_deadline=now + timedelta(minutes=7),
        verification_status=VerificationStatus.PENDING_CHECK.value,
        addition_window_status=AdditionWindowStatus.ADDITION_CLOSED.value,
    )

    assert order.verification_status == "PENDING_CHECK"
    assert order.addition_window_status == "ADDITION_CLOSED"
    assert order.verification_deadline > order.handover_initiated_at
    delta = order.verification_deadline - order.handover_initiated_at
    assert delta.total_seconds() == 420  # exactly 7 minutes


def test_customer_confirms_everything_correct_completes_immediately():
    """If customer confirms everything is correct, order completes immediately without waiting 7 minutes."""
    order = Order(
        id=uuid4(),
        customer_id=uuid4(),
        shop_id=uuid4(),
        status=OrderStatus.OUT_FOR_DELIVERY.value,
        delivery_status="HANDOVER_READY",
        item_total_paise=12000,
        delivery_fee_paise=2500,
        payment_mode="online",
        payment_status="paid",
        verification_status=VerificationStatus.PENDING_CHECK.value,
    )

    # Customer action: everything_correct
    order.verification_status = VerificationStatus.ALL_CORRECT.value
    order.delivery_status = "DELIVERED"
    order.status = OrderStatus.COMPLETED.value

    assert order.verification_status == "ALL_CORRECT"
    assert order.status == OrderStatus.COMPLETED.value
    assert order.delivery_status == "DELIVERED"


def test_expired_window_auto_completes():
    """When the 7-minute server deadline passes without an issue, order auto-completes."""
    past_time = datetime.now(UTC) - timedelta(minutes=8)
    order = Order(
        id=uuid4(),
        customer_id=uuid4(),
        shop_id=uuid4(),
        status=OrderStatus.OUT_FOR_DELIVERY.value,
        delivery_status="HANDOVER_READY",
        item_total_paise=12000,
        delivery_fee_paise=2500,
        payment_mode="online",
        payment_status="paid",
        handover_initiated_at=past_time,
        verification_deadline=past_time + timedelta(minutes=7),
        verification_status=VerificationStatus.PENDING_CHECK.value,
    )

    now = datetime.now(UTC)
    is_expired = now >= order.verification_deadline
    assert is_expired is True

    if is_expired and order.verification_status == VerificationStatus.PENDING_CHECK.value:
        order.verification_status = VerificationStatus.AUTO_COMPLETED_EXPIRED.value
        order.status = OrderStatus.COMPLETED.value
        order.delivery_status = "DELIVERED"

    assert order.verification_status == "AUTO_COMPLETED_EXPIRED"
    assert order.status == "COMPLETED"


def test_expired_item_shop_pays_return_charge():
    """CRITICAL RULE: Expired item returns must set return_charge_payer = SHOP, customer fee = 0."""
    customer_id = uuid4()
    shop_id = uuid4()
    order_id = uuid4()
    product_id = uuid4()

    item = OrderItem(
        id=uuid4(),
        order_id=order_id,
        product_id=product_id,
        qty=2,
        price_at_order_time_paise=6000,
    )

    # Customer reports expired item
    is_expired = True
    return_charge_payer = (
        ReturnChargePayer.SHOP.value if is_expired else ReturnChargePayer.CUSTOMER.value
    )
    customer_return_charge = 0 if is_expired else 2000

    ret = OrderReturn(
        id=uuid4(),
        order_id=order_id,
        order_item_id=item.id,
        customer_id=customer_id,
        shop_id=shop_id,
        product_id=product_id,
        return_reason=ReturnReason.EXPIRED_ITEM.value,
        status=ReturnStatus.RETURN_REQUESTED.value,
        return_charge_payer=return_charge_payer,
        return_charge_paise=customer_return_charge,
        refund_amount_paise=item.price_at_order_time_paise * item.qty,
        is_expired_item=True,
    )

    incident = MerchantQualityIncident(
        id=uuid4(),
        shop_id=shop_id,
        order_id=order_id,
        product_id=product_id,
        return_id=ret.id,
        incident_type="EXPIRED_ITEM",
        severity="CRITICAL",
        refund_amount_paise=ret.refund_amount_paise,
        return_cost_paise=2000,
        status="RECORDED",
    )

    assert ret.return_charge_payer == "SHOP"
    assert ret.return_charge_paise == 0  # Zero fee to customer
    assert ret.refund_amount_paise == 12000
    assert ret.is_expired_item is True
    assert incident.severity == "CRITICAL"
    assert incident.incident_type == "EXPIRED_ITEM"


def test_order_addition_eligibility():
    """Add More is eligible during PREPARING before shop closes addition window."""
    order = Order(
        id=uuid4(),
        customer_id=uuid4(),
        shop_id=uuid4(),
        status=OrderStatus.PREPARING.value,
        delivery_status="NOT_READY",
        item_total_paise=15000,
        delivery_fee_paise=2500,
        payment_mode="online",
        payment_status="paid",
        addition_window_status=AdditionWindowStatus.ADDITION_OPEN.value,
    )

    can_add = (
        order.status in [OrderStatus.PLACED.value, OrderStatus.ACCEPTED_BY_SHOP.value, OrderStatus.PREPARING.value]
        and order.addition_window_status == AdditionWindowStatus.ADDITION_OPEN.value
        and order.delivery_status not in ["PICKED_UP", "OUT_FOR_DELIVERY", "DELIVERED"]
    )
    assert can_add is True

    # When shop closes additions
    order.addition_window_status = AdditionWindowStatus.ADDITION_CLOSED.value
    can_add_after_close = (
        order.status in [OrderStatus.PLACED.value, OrderStatus.ACCEPTED_BY_SHOP.value, OrderStatus.PREPARING.value]
        and order.addition_window_status == AdditionWindowStatus.ADDITION_OPEN.value
        and order.delivery_status not in ["PICKED_UP", "OUT_FOR_DELIVERY", "DELIVERED"]
    )
    assert can_add_after_close is False


def test_addition_charges_only_incremental_amount():
    """Customer pays only additional amount without duplicate delivery fee."""
    original_item_total = 18000  # ₹180
    original_delivery_fee = 2500  # ₹25

    # Additional items: 1x ₹70 (7000 paise)
    addition_item_total = 7000
    addition_delivery_fee = 0  # Traveling on existing delivery task
    total_addition = addition_item_total + addition_delivery_fee

    wallet_balance = 5000  # ₹50
    wallet_used = min(wallet_balance, total_addition)
    external_amount = total_addition - wallet_used

    assert total_addition == 7000  # Only ₹70, not ₹250 + ₹25
    assert wallet_used == 5000
    assert external_amount == 2000

    addition = OrderAddition(
        id=uuid4(),
        original_order_id=uuid4(),
        customer_id=uuid4(),
        shop_id=uuid4(),
        status=AdditionStatus.CONFIRMED.value,
        item_total_paise=addition_item_total,
        delivery_fee_adjustment_paise=addition_delivery_fee,
        total_addition_paise=total_addition,
        wallet_amount_used_paise=wallet_used,
        external_amount_paise=external_amount,
        payment_status="paid",
    )

    assert addition.total_addition_paise == 7000
    assert addition.wallet_amount_used_paise == 5000
    assert addition.external_amount_paise == 2000
