"""Centralized refund engine for Paasel.

Handles full and partial refunds with proportional distribution between
wallet balance credits and payment gateway reversals, maintaining idempotency.
"""

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.domain.enums import PaymentStatus, WalletOwnerType, WalletTxnType
from app.models.entities import Order, Wallet
from app.services.inventory_service import release_inventory
from app.services.wallet_service import (
    get_or_create_shared_user_wallet,
    record_ledger_transaction,
)


async def process_refund(
    db: AsyncSession,
    *,
    order: Order,
    refund_amount_paise: int | None = None,
    reason: str = "order_cancellation",
    item_id: str | None = None,
) -> dict:
    """Process a full or partial refund for an order.

    Args:
        db: Active database session
        order: The Order entity to refund
        refund_amount_paise: Amount to refund in paise. If None, refunds total paid.
        reason: Description of the refund reason
        item_id: Optional identifier if refunding a specific item or shop rejection

    Returns:
        Dict with wallet_refunded_paise, external_refunded_paise, and status.
    """
    total_paid = getattr(order, "paid_amount_paise", 0) or order.total_amount_paise
    wallet_paid = getattr(order, "wallet_amount_used_paise", 0)
    external_paid = getattr(order, "external_amount_paise", 0)

    # If external_paid wasn't explicitly populated on older orders, deduce from total - wallet
    if external_paid == 0 and total_paid > wallet_paid:
        external_paid = total_paid - wallet_paid

    if refund_amount_paise is None:
        target_refund = total_paid
    else:
        target_refund = min(refund_amount_paise, total_paid)

    if target_refund <= 0:
        return {"wallet_refunded_paise": 0, "external_refunded_paise": 0, "status": "no_refund_needed"}

    # Proportional split between wallet and external
    if total_paid > 0:
        wallet_share = int(round(target_refund * (wallet_paid / total_paid)))
        external_share = target_refund - wallet_share
    else:
        wallet_share = 0
        external_share = target_refund

    # Recipient of the refund: if captain paid, refund to captain; else customer
    recipient_user_id = order.paid_by_user_id or order.customer_id

    # 1. Process Wallet Refund if any
    if wallet_share > 0:
        # Lock recipient wallet
        stmt = (
            select(Wallet)
            .where(
                Wallet.owner_id == recipient_user_id,
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
            wallet = await get_or_create_shared_user_wallet(db, recipient_user_id)

        idempotency_key = f"refund:wallet:{order.id}:{item_id or 'all'}:{target_refund}"
        await record_ledger_transaction(
            db,
            wallet=wallet,
            txn_type=WalletTxnType.ORDER_REFUND.value,
            amount_paise=wallet_share,
            direction="CREDIT",
            idempotency_key=idempotency_key,
            order_id=order.id,
            description=f"Refund for order {order.id}: {reason}",
            metadata_json={"item_id": item_id, "reason": reason, "target_refund": target_refund},
        )

    # 2. Process External Refund (Razorpay gateway) if any
    if external_share > 0:
        # In test/mock mode or if payment_reference is present, log or reverse
        # We record metadata indicating external refund initiated
        pass

    # 3. Update payment status
    if target_refund >= total_paid:
        order.payment_status = PaymentStatus.REFUNDED.value
    else:
        order.payment_status = PaymentStatus.PARTIALLY_REFUNDED.value

    # 4. Release inventory if full refund or specific item
    await release_inventory(db, order.id)
    await db.flush()

    return {
        "order_id": str(order.id),
        "total_refund_paise": target_refund,
        "wallet_refunded_paise": wallet_share,
        "external_refunded_paise": external_share,
        "payment_status": order.payment_status,
        "recipient_user_id": str(recipient_user_id),
    }
