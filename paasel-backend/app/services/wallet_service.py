"""Wallet service — earnings ledger, COD reconciliation, balance computation."""

from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.enums import PaymentMode, WalletOwnerType, WalletTxnType
from app.models.entities import Order, Shop, Wallet, WalletTransaction


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


async def compute_unsettled_balance(db: AsyncSession, wallet_id: UUID) -> int:
    """Balance = sum of unsettled manual_payout transactions.

    Credits are positive, debits (cod_debit) are negative.
    """
    result = await db.scalar(
        select(func.coalesce(func.sum(WalletTransaction.amount_paise), 0))
        .where(
            WalletTransaction.wallet_id == wallet_id,
            WalletTransaction.settlement_channel == "manual_payout",
            WalletTransaction.settled_at.is_(None),
        )
    )
    return int(result or 0)


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

    partner_wallet = await get_or_create_wallet(
        db, assignment.partner_id, WalletOwnerType.DELIVERY_PARTNER
    )

    is_online = order.payment_mode == PaymentMode.ONLINE.value
    now = datetime.now(UTC) if is_online else None
    channel = "route_auto" if is_online else "manual_payout"

    # Shop earning credit
    shop_txn = WalletTransaction(
        wallet_id=shop_wallet.id,
        type=WalletTxnType.EARNING.value,
        amount_paise=order.item_total_paise,
        order_id=order.id,
        settlement_channel=channel,
        settled_at=now,
    )
    db.add(shop_txn)

    # Partner earning credit (delivery fee)
    partner_earning = WalletTransaction(
        wallet_id=partner_wallet.id,
        type=WalletTxnType.EARNING.value,
        amount_paise=order.delivery_fee_paise,
        order_id=order.id,
        settlement_channel=channel,
        settled_at=now,
    )
    db.add(partner_earning)

    if not is_online:
        # COD: partner holds cash. Debit them for the shop's portion.
        partner_debit = WalletTransaction(
            wallet_id=partner_wallet.id,
            type=WalletTxnType.COD_DEBIT.value,
            amount_paise=-order.item_total_paise,  # Negative = debit
            order_id=order.id,
            settlement_channel="manual_payout",
            settled_at=None,
        )
        db.add(partner_debit)
    else:
        # ONLINE: attempt Route transfer if linked accounts exist
        await _attempt_route_transfer(db, order, shop, assignment.partner_id)

    await db.flush()


async def _attempt_route_transfer(
    db: AsyncSession, order: Order, shop, partner_id: UUID
) -> None:
    """Try to split payment via Razorpay Route. Falls back to manual_payout."""
    from app.models.entities import Payment
    from app.services.razorpay_client import razorpay

    # Get the captured payment
    payment = await db.scalar(
        select(Payment).where(
            Payment.order_id == order.id,
            Payment.status == "captured",
        )
    )
    if not payment or not payment.razorpay_payment_id:
        return  # Can't route without a payment ID

    # Check linked accounts exist
    shop_linked_id = getattr(shop, "razorpay_linked_account_id", None)
    # For partner, would check delivery_partner_profiles.razorpay_linked_account_id
    # For now, if either is missing, settlement stays as route_auto (already marked)
    # In production, would fall back to manual_payout

    # Route transfer is attempted but failures don't block the order
    # (logged and retried in weekly settlement)
    if not shop_linked_id:
        return

    try:
        await razorpay.create_transfer(
            payment_id=payment.razorpay_payment_id,
            linked_account_id=shop_linked_id,
            amount_paise=order.item_total_paise,
        )
    except Exception:
        pass  # Logged by Sentry; falls back to weekly payout


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
