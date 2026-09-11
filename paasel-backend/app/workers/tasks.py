"""Celery tasks — assignment timeout, customer decision timeout."""

import asyncio
from uuid import UUID

from app.worker import celery_app


def _run_async(coro):
    """Run an async function from a sync Celery task."""
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


@celery_app.task(name="paasel.assignment_timeout_check")
def assignment_timeout_check(
    assignment_id: str, order_id: str, cascade_count: int
) -> dict:
    """Fires 35s after an assignment offer. If still un-accepted, expire and cascade."""
    return _run_async(_handle_assignment_timeout(
        UUID(assignment_id), UUID(order_id), cascade_count
    ))


@celery_app.task(name="paasel.batch_offer_timeout_check")
def batch_offer_timeout_check(assignment_id: str, order_id: str) -> dict:
    """Fires 20s after a Tier 2 detour offer.

    An unanswered detour is not a failure of the order — it just means batching
    did not pan out. The offer is expired and the order falls through to a
    normal fresh search, as if Tier 2 had never run.
    """
    return _run_async(_handle_batch_offer_timeout(
        UUID(assignment_id), UUID(order_id)
    ))


@celery_app.task(name="paasel.stale_online_sweep")
def stale_online_sweep() -> dict:
    """Every 5 minutes: force is_online=false for partners who stopped pinging.

    Matching already ignores partners without a recent ping, so this is not
    about protecting dispatch. It is about the partner's own dashboard: without
    the sweep, someone whose app was killed re-opens it and is told they are
    still online and available, which is both confusing and untrue.
    """
    return _run_async(_handle_stale_online_sweep())


@celery_app.task(name="paasel.customer_decision_timeout")
def customer_decision_timeout(order_id: str) -> dict:
    """Fires 7 minutes after AWAITING_CUSTOMER_DECISION. Auto-proceeds."""
    return _run_async(_handle_customer_decision_timeout(UUID(order_id)))


@celery_app.task(name="paasel.payment_expiry_check")
def payment_expiry_check(order_id: str) -> dict:
    """Fires 15 min after payment.failed — cancels if still unpaid."""
    return _run_async(_handle_payment_expiry(UUID(order_id)))


@celery_app.task(name="paasel.weekly_settlement")
def weekly_settlement() -> dict:
    """Weekly payout job — settles all manual_payout balances."""
    return _run_async(_handle_weekly_settlement())


@celery_app.task(name="paasel.daily_subscription_check")
def daily_subscription_check() -> dict:
    """Daily: check trial expiry and grace period suspension."""
    return _run_async(_handle_daily_subscription_check())


async def _handle_assignment_timeout(
    assignment_id: UUID, order_id: UUID, cascade_count: int
) -> dict:
    from sqlalchemy import select
    from app.core.database import SessionFactory
    from app.models.entities import DeliveryAssignment, Order
    from app.services.partner_matching import run_matching

    async with SessionFactory() as db:
        assignment = await db.get(DeliveryAssignment, assignment_id)
        if not assignment:
            return {"action": "skipped", "reason": "assignment_not_found"}

        # Only expire if not yet accepted
        if assignment.accepted_at is not None:
            return {"action": "skipped", "reason": "already_accepted"}

        # Mark expired (we use accepted_at=None as "still offered")
        # Delete the expired assignment to keep things clean
        await db.delete(assignment)

        order = await db.get(Order, order_id)
        if not order:
            await db.commit()
            return {"action": "skipped", "reason": "order_not_found"}

        # Collect all previously offered partner IDs for this order
        prev_assignments = (await db.execute(
            select(DeliveryAssignment.partner_id).where(
                DeliveryAssignment.order_id == order_id
            )
        )).scalars().all()
        excluded = list(prev_assignments) + [assignment.partner_id]

        await db.commit()

        # Re-run matching with cascade
        new_cascade = cascade_count + 1
        if new_cascade > 5:
            return {"action": "flagged_for_admin", "cascades": new_cascade}

        async with SessionFactory() as db2:
            order2 = await db2.get(Order, order_id)
            if order2:
                result = await run_matching(
                    db2, order2, cascade_count=new_cascade, excluded_ids=excluded
                )
                if result:
                    return {"action": "re_offered", "cascade": new_cascade}
            return {"action": "no_partner_found", "cascade": new_cascade}


async def _handle_batch_offer_timeout(
    assignment_id: UUID, order_id: UUID
) -> dict:
    from app.core.database import SessionFactory
    from app.services.batch_offers import expire_batch_offer

    async with SessionFactory() as db:
        outcome = await expire_batch_offer(db, assignment_id)
        await db.commit()

    if outcome == "already_accepted":
        return {"action": "skipped", "reason": "already_accepted"}
    if outcome == "not_found":
        return {"action": "skipped", "reason": "assignment_not_found"}

    # Fall through to a plain fresh search for this order.
    from app.core.database import SessionFactory as Factory
    from app.models.entities import Order
    from app.services.partner_matching import run_matching

    async with Factory() as db2:
        order = await db2.get(Order, order_id)
        if not order:
            return {"action": "skipped", "reason": "order_not_found"}
        assignment = await run_matching(db2, order, allow_batching=False)

    if assignment:
        return {"action": "fell_through_to_fresh", "order_id": str(order_id)}
    return {"action": "no_partner_found", "order_id": str(order_id)}


async def _handle_stale_online_sweep() -> dict:
    from sqlalchemy import text

    from app.core.database import SessionFactory
    from app.services.batch_offers import STALE_ONLINE_THRESHOLD_SECONDS

    async with SessionFactory() as db:
        result = await db.execute(
            text("""
                UPDATE delivery_partner_profiles dp
                SET is_online = false
                WHERE dp.is_online = true
                  AND NOT EXISTS (
                    SELECT 1 FROM live_locations ll
                    WHERE ll.partner_id = dp.user_id
                      AND ll.updated_at
                          > now() - make_interval(secs => :threshold)
                  )
                RETURNING dp.user_id
            """),
            {"threshold": STALE_ONLINE_THRESHOLD_SECONDS},
        )
        swept = [str(row[0]) for row in result.all()]
        await db.commit()

    return {"forced_offline": len(swept), "partner_ids": swept}


async def _handle_customer_decision_timeout(order_id: UUID) -> dict:
    from app.core.database import SessionFactory
    from app.services.missing_item import auto_proceed_on_timeout

    async with SessionFactory() as db:
        await auto_proceed_on_timeout(db, order_id)
        return {"action": "auto_proceeded", "order_id": str(order_id)}


async def _handle_payment_expiry(order_id: UUID) -> dict:
    from app.core.database import SessionFactory
    from app.domain.enums import OrderStatus
    from app.models.entities import Order
    from app.services.order_state_machine import transition

    async with SessionFactory() as db:
        order = await db.get(Order, order_id)
        if not order:
            return {"action": "skipped", "reason": "order_not_found"}
        if getattr(order, "payment_status", "") == "paid":
            return {"action": "skipped", "reason": "already_paid"}
        if order.status != OrderStatus.PLACED.value:
            return {"action": "skipped", "reason": "not_in_placed_state"}

        await transition(db, order, OrderStatus.CANCELLED_BY_CUSTOMER)
        await db.commit()
        return {"action": "cancelled", "order_id": str(order_id)}


async def _handle_weekly_settlement() -> dict:
    from sqlalchemy import select, func
    from app.core.database import SessionFactory
    from app.models.entities import Wallet, WalletTransaction

    settled_count = 0
    flagged_count = 0

    async with SessionFactory() as db:
        # Find all wallets with unsettled manual_payout balance
        wallets = (await db.execute(select(Wallet))).scalars().all()

        for wallet in wallets:
            balance = await db.scalar(
                select(func.coalesce(func.sum(WalletTransaction.amount_paise), 0))
                .where(
                    WalletTransaction.wallet_id == wallet.id,
                    WalletTransaction.settlement_channel == "manual_payout",
                    WalletTransaction.settled_at.is_(None),
                )
            )
            balance = int(balance or 0)

            if balance == 0:
                continue

            if balance > 0:
                # Platform owes them — create payout (simulated)
                from datetime import UTC, datetime
                # Mark transactions as settled
                unsettled = (await db.execute(
                    select(WalletTransaction).where(
                        WalletTransaction.wallet_id == wallet.id,
                        WalletTransaction.settlement_channel == "manual_payout",
                        WalletTransaction.settled_at.is_(None),
                    )
                )).scalars().all()
                for txn in unsettled:
                    txn.settled_at = datetime.now(UTC)
                settled_count += 1

            elif balance < -200000:  # ₹2000 threshold
                flagged_count += 1
            # Negative balance < threshold: nets against next week

        await db.commit()

    return {"settled": settled_count, "flagged": flagged_count}


async def _handle_daily_subscription_check() -> dict:
    from app.core.database import SessionFactory
    from app.services.subscription_service import (
        check_grace_period_expiry,
        check_trial_expiry,
    )

    async with SessionFactory() as db:
        past_due = await check_trial_expiry(db)
        suspended = await check_grace_period_expiry(db)

    return {
        "past_due_count": len(past_due),
        "suspended_count": len(suspended),
    }
