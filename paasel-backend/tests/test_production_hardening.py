"""Production hardening tests — order types, inventory reservation, group order packages,

payment decoupling state machine guards, captain payment attribution, and refund logic.
"""

from datetime import UTC, datetime, timedelta
from uuid import uuid4
from unittest.mock import AsyncMock

import pytest

from app.core.errors import AppError
from app.domain.enums import (
    DeliveryStatus,
    GroupOrderStatus,
    HandoverType,
    InventoryReservationStatus,
    OrderStatus,
    OrderType,
    PaymentMode,
    PaymentStatus,
    UserRole,
    WalletTxnType,
)
from app.models.entities import (
    CustomerProfile,
    GroupOrderCartItem,
    GroupOrderMember,
    GroupOrderPackage,
    GroupOrderSession,
    InventoryReservation,
    Order,
    OrderItem,
    OrderPhoto,
    Product,
    Shop,
    User,
    Wallet,
)
from app.services.order_state_machine import clear_hooks, transition


@pytest.fixture(autouse=True)
def _clear():
    clear_hooks()
    yield
    clear_hooks()


# ---------------------------------------------------------------------------
# 1. Entity and Schema Validations
# ---------------------------------------------------------------------------


def test_order_type_and_production_fields():
    """Verify Order entity has order_type, external_amount_paise, and captain payment attribution."""
    order_id = uuid4()
    customer_id = uuid4()
    captain_id = uuid4()
    session_id = uuid4()

    order = Order(
        id=order_id,
        customer_id=customer_id,
        shop_id=uuid4(),
        status=OrderStatus.PLACED.value,
        order_type=OrderType.GROUP_ORDER.value,
        group_session_id=session_id,
        item_total_paise=10000,
        delivery_fee_paise=0,
        payment_mode="online",
        payment_status="paid",
        wallet_amount_used_paise=2000,
        external_amount_paise=8000,
        paid_by_user_id=captain_id,
        paid_by_role="captain",
        delivery_otp="4321",
    )
    assert order.order_type == OrderType.GROUP_ORDER.value
    assert order.group_session_id == session_id
    assert order.customer_id == customer_id  # Ownership is preserved
    assert order.paid_by_user_id == captain_id  # Financial attribution
    assert order.paid_by_role == "captain"
    assert order.external_amount_paise == 8000
    assert order.wallet_amount_used_paise == 2000


def test_inventory_reservation_entity():
    """Verify InventoryReservation entity states and relations."""
    res_id = uuid4()
    order_id = uuid4()
    product_id = uuid4()
    expires = datetime.now(UTC) + timedelta(minutes=10)

    res = InventoryReservation(
        id=res_id,
        order_id=order_id,
        product_id=product_id,
        qty=3,
        status=InventoryReservationStatus.RESERVED.value,
        expires_at=expires,
    )
    assert res.status == "RESERVED"
    assert res.qty == 3
    assert res.expires_at == expires

    # State transitions
    res.status = InventoryReservationStatus.COMMITTED.value
    assert res.status == "COMMITTED"
    res.status = InventoryReservationStatus.RELEASED.value
    assert res.status == "RELEASED"


def test_group_order_package_entity():
    """Verify GroupOrderPackage entity structure, verification code, and handover types."""
    pkg_id = uuid4()
    session_id = uuid4()
    order_id = uuid4()
    shop_id = uuid4()
    member_id = uuid4()

    pkg = GroupOrderPackage(
        id=pkg_id,
        session_id=session_id,
        order_id=order_id,
        shop_id=shop_id,
        member_id=member_id,
        handover_otp="8899",
        pickup_status="PENDING",
        delivery_status="NOT_READY",
        handover_status="PENDING",
        handover_type=HandoverType.DIRECT_TO_MEMBER.value,
    )
    assert pkg.handover_otp == "8899"
    assert pkg.pickup_status == "PENDING"
    assert pkg.delivery_status == "NOT_READY"
    assert pkg.handover_status == "PENDING"
    assert pkg.handover_type == "DIRECT_TO_MEMBER"


def test_group_order_session_deadlines_and_payment_complete():
    """Verify GroupOrderSession deadline fields and payment_complete flag."""
    now = datetime.now(UTC)
    session = GroupOrderSession(
        id=uuid4(),
        creator_id=uuid4(),
        society_name="Greenwood Heights",
        status=GroupOrderStatus.OPEN,
        private_cart_mode=True,
        join_deadline=now + timedelta(minutes=15),
        cart_deadline=now + timedelta(minutes=30),
        payment_deadline=now + timedelta(minutes=45),
        locked_at=None,
        payment_complete=False,
    )
    assert session.private_cart_mode is True
    assert session.payment_complete is False
    assert session.join_deadline > now
    assert session.payment_deadline > session.cart_deadline

    # Marking payment complete
    session.payment_complete = True
    assert session.payment_complete is True


# ---------------------------------------------------------------------------
# 2. State Machine Guards (Decoupling & Group Gate)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_guard_unpaid_order_cannot_reach_delivered():
    """Guard: transition OUT_FOR_DELIVERY -> DELIVERED must fail if unpaid."""
    db = AsyncMock()
    order = Order(
        id=uuid4(),
        customer_id=uuid4(),
        shop_id=uuid4(),
        status=OrderStatus.OUT_FOR_DELIVERY.value,
        payment_mode="online",
        payment_status="pending",  # UNPAID!
        delivery_otp="1234",
    )
    # Mock photo check passing
    db.scalar.return_value = 1

    with pytest.raises(AppError) as exc_info:
        await transition(db, order, OrderStatus.DELIVERED, otp="1234")
    assert "Order must be paid before delivery" in str(exc_info.value.message)


@pytest.mark.asyncio
async def test_guard_group_order_cannot_be_delivered_if_session_unpaid():
    """Group order gate: delivery must fail if GroupOrderSession.payment_complete is False."""
    db = AsyncMock()
    session_id = uuid4()
    session = GroupOrderSession(
        id=session_id,
        creator_id=uuid4(),
        society_name="Sunrise Enclave",
        status=GroupOrderStatus.PROCESSING,
        payment_complete=False,  # Still pending member payments!
    )
    order = Order(
        id=uuid4(),
        customer_id=uuid4(),
        shop_id=uuid4(),
        status=OrderStatus.OUT_FOR_DELIVERY.value,
        payment_mode="online",
        payment_status="paid",  # This member order is paid, but group as a whole isn't
        delivery_otp="1234",
        group_session_id=session_id,
    )
    # Photo check returns 1
    db.scalar.return_value = 1
    # get(GroupOrderSession, session_id) returns the session
    db.get.return_value = session

    with pytest.raises(AppError) as exc_info:
        await transition(db, order, OrderStatus.DELIVERED, otp="1234")
    assert exc_info.value.code == "group_payment_incomplete"


@pytest.mark.asyncio
async def test_group_order_delivers_when_session_payment_complete():
    """Group order succeeds in delivery when GroupOrderSession.payment_complete is True."""
    db = AsyncMock()
    session_id = uuid4()
    session = GroupOrderSession(
        id=session_id,
        creator_id=uuid4(),
        society_name="Sunrise Enclave",
        status=GroupOrderStatus.PROCESSING,
        payment_complete=True,  # All members paid!
    )
    order = Order(
        id=uuid4(),
        customer_id=uuid4(),
        shop_id=uuid4(),
        status=OrderStatus.OUT_FOR_DELIVERY.value,
        payment_mode="online",
        payment_status="paid",
        delivery_otp="1234",
        group_session_id=session_id,
    )
    db.scalar.return_value = 1
    db.get.return_value = session

    result = await transition(db, order, OrderStatus.DELIVERED, otp="1234")
    assert result.status == OrderStatus.DELIVERED.value


# ---------------------------------------------------------------------------
# 3. Proportional Refund Calculation Logic
# ---------------------------------------------------------------------------


def test_proportional_refund_calculation():
    """Verify split calculations between wallet and payment gateway reversals."""
    # Scenario 1: ₹100 order paid ₹40 wallet + ₹60 external -> ₹100 refund
    total_paid = 10000
    wallet_paid = 4000
    target_refund = 10000
    wallet_share = int(round(target_refund * (wallet_paid / total_paid)))
    external_share = target_refund - wallet_share
    assert wallet_share == 4000
    assert external_share == 6000

    # Scenario 2: Partial refund of ₹25 on above order
    target_refund = 2500
    wallet_share = int(round(target_refund * (wallet_paid / total_paid)))
    external_share = target_refund - wallet_share
    assert wallet_share == 1000  # 40% of 2500
    assert external_share == 1500  # 60% of 2500

    # Scenario 3: 100% wallet paid order
    wallet_paid = 10000
    target_refund = 5000
    wallet_share = int(round(target_refund * (wallet_paid / total_paid)))
    external_share = target_refund - wallet_share
    assert wallet_share == 5000
    assert external_share == 0


def test_captain_attribution_financial_rule():
    """Verify captain payment preserves order owner while setting paid_by_user_id and paid_by_role."""
    member_id = uuid4()
    captain_id = uuid4()
    order = Order(
        id=uuid4(),
        customer_id=member_id,
        shop_id=uuid4(),
        status=OrderStatus.PLACED.value,
        order_type=OrderType.GROUP_ORDER.value,
        item_total_paise=5000,
        external_amount_paise=5000,
        payment_status="paid",
        paid_by_user_id=captain_id,
        paid_by_role="captain",
    )
    # The member owns the items
    assert order.customer_id == member_id
    # The refund or payer tracking points to captain
    payer = order.paid_by_user_id or order.customer_id
    assert payer == captain_id
    assert order.paid_by_role == "captain"
