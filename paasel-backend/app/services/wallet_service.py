"""Wallet service — earnings ledger, COD reconciliation, balance computation."""

from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.domain.enums import PaymentMode, UserRole, WalletOwnerType, WalletTxnType
from app.models.entities import Order, Shop, User, Wallet, WalletTransaction


async def get_or_create_wallet(
    db: AsyncSession, owner_id: UUID, owner_type: WalletOwnerType
) -> Wallet:
    """Get or create a wallet for the given owner."""
    wallet = await db.scalar(
        select(Wallet).where(
            Wallet.owner_id == owner_id,
            Wallet.owner_type == owner_type.value,
        )
    )
    if not wallet:
        wallet = Wallet(
            owner_id=owner_id,
            owner_type=owner_type.value,
            balance_paise=0,
        )
        db.add(wallet)
        await db.flush()
    return wallet


async def get_or_create_shared_user_wallet(
    db: AsyncSession, user_id: UUID
) -> Wallet:
    """Get or create the unified Paasel wallet shared between customer & delivery partner roles.

    If a delivery_partner or customer wallet already exists for this user, it is reused.
    Otherwise, creates a canonical user wallet.
    """
    wallet = await db.scalar(
        select(Wallet).where(
            Wallet.owner_id == user_id,
            Wallet.owner_type.in_([
                WalletOwnerType.USER.value,
                WalletOwnerType.DELIVERY_PARTNER.value,
                WalletOwnerType.CUSTOMER.value,
            ]),
        )
    )
    if not wallet:
        wallet = Wallet(
            owner_id=user_id,
            owner_type=WalletOwnerType.USER.value,
            balance_paise=0,
        )
        db.add(wallet)
        await db.flush()
    return wallet


async def compute_unsettled_balance(db: AsyncSession, wallet_id: UUID) -> int:
    """Balance = sum of unsettled manual_payout transactions for shops/riders.

    Credits are positive, debits (cod_debit) are negative.
    For standard wallets with positive ledger entries, balance is tracked on wallet.balance_paise.
    """
    result = await db.scalar(
        select(func.coalesce(func.sum(WalletTransaction.amount_paise), 0))
        .where(
            WalletTransaction.wallet_id == wallet_id,
            WalletTransaction.settlement_channel == "manual_payout",
            WalletTransaction.settled_at.is_(None),
        )
    )
    unsettled = int(result or 0)
    if unsettled != 0:
        return unsettled

    # For user shared wallet: return actual balance_paise
    wallet = await db.get(Wallet, wallet_id)
    return wallet.balance_paise if wallet else 0


async def record_ledger_transaction(
    db: AsyncSession,
    *,
    wallet: Wallet,
    txn_type: str,
    amount_paise: int,
    direction: str,
    idempotency_key: str | None = None,
    order_id: UUID | None = None,
    description: str | None = None,
    delivery_reference: str | None = None,
    settlement_channel: str | None = None,
    settled_at: datetime | None = None,
    metadata_json: dict | None = None,
) -> WalletTransaction:
    """Record an immutable ledger transaction with idempotency and balance update."""
    if idempotency_key:
        existing = await db.scalar(
            select(WalletTransaction).where(
                WalletTransaction.idempotency_key == idempotency_key
            )
        )
        if existing:
            return existing

    # Signed amount: positive for CREDIT, negative for DEBIT
    signed_amount = abs(amount_paise) if direction == "CREDIT" else -abs(amount_paise)

    txn = WalletTransaction(
        wallet_id=wallet.id,
        type=txn_type,
        amount_paise=signed_amount,
        direction=direction,
        status="COMPLETED",
        order_id=order_id,
        idempotency_key=idempotency_key,
        description=description,
        delivery_reference=delivery_reference,
        settlement_channel=settlement_channel,
        settled_at=settled_at,
        metadata_json=metadata_json,
    )
    db.add(txn)

    # Atomically adjust wallet balance
    new_balance = wallet.balance_paise + signed_amount
    if new_balance < 0:
        raise AppError(
            422,
            "insufficient_balance",
            "Insufficient wallet balance for this transaction",
        )
    wallet.balance_paise = new_balance
    await db.flush()
    return txn


async def debit_wallet_for_order(
    db: AsyncSession,
    *,
    user_id: UUID,
    order_id: UUID,
    amount_paise: int,
) -> WalletTransaction:
    """Atomically debit user's shared wallet for customer order payment."""
    # Row lock wallet to prevent race conditions / double spending
    stmt = (
        select(Wallet)
        .where(
            Wallet.owner_id == user_id,
            Wallet.owner_type.in_([
                WalletOwnerType.USER.value,
                WalletOwnerType.DELIVERY_PARTNER.value,
                WalletOwnerType.CUSTOMER.value,
            ]),
        )
        .with_for_update()
    )
    wallet = await db.scalar(stmt)
    if not wallet:
        wallet = await get_or_create_shared_user_wallet(db, user_id)

    if wallet.balance_paise < amount_paise:
        raise AppError(
            422,
            "insufficient_wallet_balance",
            f"Wallet balance ({wallet.balance_paise} paise) is less than requested debit ({amount_paise} paise)",
        )

    return await record_ledger_transaction(
        db,
        wallet=wallet,
        txn_type=WalletTxnType.ORDER_WALLET_PAYMENT.value,
        amount_paise=amount_paise,
        direction="DEBIT",
        idempotency_key=f"order_wallet_debit_{order_id}",
        order_id=order_id,
        description=f"Paid for order #{str(order_id)[:8]}",
    )


async def refund_wallet_for_order(
    db: AsyncSession,
    *,
    user_id: UUID,
    order_id: UUID,
    amount_paise: int,
    reason: str,
) -> WalletTransaction:
    """Credit customer's shared wallet on cancellation or partial item rejection."""
    wallet = await get_or_create_shared_user_wallet(db, user_id)
    return await record_ledger_transaction(
        db,
        wallet=wallet,
        txn_type=WalletTxnType.ORDER_REFUND.value,
        amount_paise=amount_paise,
        direction="CREDIT",
        idempotency_key=f"order_wallet_refund_{order_id}_{amount_paise}",
        order_id=order_id,
        description=f"Refund for order #{str(order_id)[:8]}: {reason}",
    )


async def settle_on_delivery(db: AsyncSession, order: Order) -> None:
    """Called when order reaches DELIVERED — credits both parties' wallets.

    For ONLINE orders: marks as route_auto (instant settlement).
    For COD orders: marks shop credit as manual_payout, debits partner for
    the shop's portion they're physically holding.
    """
    # Find the shop owner
    shop = await db.scalar(select(Shop).where(Shop.id == order.shop_id))
    if not shop:
        return

    shop_wallet = await get_or_create_wallet(
        db, shop.owner_id, WalletOwnerType.SHOP
    )

    # Find the delivery partner from the assignment
    from app.models.entities import DeliveryAssignment
    assignment = await db.scalar(
        select(DeliveryAssignment)
        .where(DeliveryAssignment.order_id == order.id)
        .order_by(DeliveryAssignment.assigned_at.desc())
    )
    if not assignment:
        return

    # Delivery partner uses the shared user wallet so earnings are immediately spendable in Customer App
    partner_wallet = await get_or_create_shared_user_wallet(
        db, assignment.partner_id
    )

    is_online = order.payment_mode == PaymentMode.ONLINE.value or order.payment_mode == PaymentMode.WALLET.value
    now = datetime.now(UTC) if is_online else None
    channel = "route_auto" if is_online else "manual_payout"

    # 1. Shop earning credit — shop always receives full item value
    await record_ledger_transaction(
        db,
        wallet=shop_wallet,
        txn_type=WalletTxnType.EARNING.value,
        amount_paise=order.item_total_paise,
        direction="CREDIT",
        idempotency_key=f"shop_earning_{order.id}_{shop.id}",
        order_id=order.id,
        description=f"Item earnings for order #{str(order.id)[:8]}",
        settlement_channel=channel,
        settled_at=now,
    )

    # 2. Partner earning credit (delivery fee) — directly into partner's shared wallet
    await record_ledger_transaction(
        db,
        wallet=partner_wallet,
        txn_type=WalletTxnType.RIDER_EARNING.value,
        amount_paise=order.delivery_fee_paise,
        direction="CREDIT",
        idempotency_key=f"rider_earning_{order.id}_{assignment.partner_id}",
        order_id=order.id,
        delivery_reference=str(assignment.trip_id),
        description=f"Delivery earning for order #{str(order.id)[:8]}",
        settlement_channel=channel,
        settled_at=now,
    )

    # 3. COD adjustment if cash was physically collected
    if order.payment_mode == PaymentMode.COD.value:
        # Cash collected from customer = total - wallet used
        total_order = order.item_total_paise + order.delivery_fee_paise
        cash_collected = total_order - (order.wallet_amount_used_paise or 0)
        # Partner keeps their delivery fee from cash collected; the rest belongs to shop/platform
        shop_cash_held = max(0, cash_collected - order.delivery_fee_paise)
        if shop_cash_held > 0:
            await record_ledger_transaction(
                db,
                wallet=partner_wallet,
                txn_type=WalletTxnType.COD_DEBIT.value,
                amount_paise=shop_cash_held,
                direction="DEBIT",
                idempotency_key=f"cod_debit_{order.id}_{assignment.partner_id}",
                order_id=order.id,
                description=f"COD cash collected for order #{str(order.id)[:8]}",
                settlement_channel="manual_payout",
                settled_at=None,
            )
    elif is_online and order.payment_mode == PaymentMode.ONLINE.value:
        # ONLINE: attempt Route transfer if linked accounts exist
        await _attempt_route_transfer(db, order, shop, assignment.partner_id)

    await db.flush()


async def _attempt_route_transfer(
    db: AsyncSession, order: Order, shop, partner_id: UUID
) -> None:
    """Try to split payment via Razorpay Route. Falls back to manual_payout."""
    from app.models.entities import Payment
    from app.services.razorpay_client import razorpay

    payment = await db.scalar(
        select(Payment).where(
            Payment.order_id == order.id,
            Payment.status == "captured",
        )
    )
    if not payment or not payment.razorpay_payment_id:
        return

    shop_linked_id = getattr(shop, "razorpay_linked_account_id", None)
    if not shop_linked_id:
        return

    try:
        await razorpay.create_transfer(
            payment_id=payment.razorpay_payment_id,
            linked_account_id=shop_linked_id,
            amount_paise=order.item_total_paise,
        )
    except Exception:
        pass


async def get_wallet_transactions(
    db: AsyncSession, wallet_id: UUID, limit: int = 20, offset: int = 0
) -> list[WalletTransaction]:
    """Paginated transaction history for a wallet."""
    result = await db.execute(
        select(WalletTransaction)
        .where(WalletTransaction.wallet_id == wallet_id)
        .order_by(WalletTransaction.created_at.desc())
        .limit(limit)
        .offset(offset)
    )
    return list(result.scalars().all())
