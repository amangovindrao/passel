"""Inventory reservation and concurrency service.

Ensures row-level locking (SELECT ... FOR UPDATE) to prevent overselling
and handles auto-release on cancellation or payment expiration.
"""

from datetime import datetime, timezone, timedelta
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.errors import AppError
from app.domain.enums import InventoryReservationStatus
from app.models.entities import InventoryReservation, Product


async def reserve_inventory(
    db: AsyncSession,
    order_id: UUID,
    items: list[dict],
    expires_in_minutes: int | None = None,
) -> list[InventoryReservation]:
    """Reserve inventory for order items with row-level locks.

    Each item in items is expected to be a dict with:
      - 'product_id': UUID
      - 'quantity': int
    """
    if expires_in_minutes is None:
        expires_in_minutes = settings.inventory_reservation_timeout_minutes

    now = datetime.now(timezone.utc)
    expires_at = now + timedelta(minutes=expires_in_minutes)
    reservations: list[InventoryReservation] = []

    # Sort product_ids deterministically to avoid deadlocks when locking multiple rows
    sorted_items = sorted(items, key=lambda x: str(x["product_id"]))

    for item in sorted_items:
        product_id = item["product_id"]
        qty = item["quantity"]
        if qty <= 0:
            continue

        stmt = select(Product).where(Product.id == product_id).with_for_update()
        product = await db.scalar(stmt)
        if not product:
            raise AppError(404, "product_not_found", f"Product {product_id} not found")

        if product.stock_quantity < qty:
            raise AppError(
                409,
                "insufficient_stock",
                f"Insufficient stock for product '{product.name}'. Available: {product.stock_quantity}, requested: {qty}",
            )

        # Deduct stock and record reservation
        product.stock_quantity -= qty
        reservation = InventoryReservation(
            order_id=order_id,
            product_id=product.id,
            qty=qty,
            status=InventoryReservationStatus.RESERVED.value,
            expires_at=expires_at,
        )
        db.add(reservation)
        reservations.append(reservation)

    await db.flush()
    return reservations


async def commit_inventory(db: AsyncSession, order_id: UUID) -> None:
    """Commit reservations when payment is confirmed or order accepted."""
    stmt = select(InventoryReservation).where(
        InventoryReservation.order_id == order_id,
        InventoryReservation.status == InventoryReservationStatus.RESERVED.value,
    )
    result = await db.scalars(stmt)
    reservations = result.all()
    for res in reservations:
        res.status = InventoryReservationStatus.COMMITTED.value
    await db.flush()


async def release_inventory(db: AsyncSession, order_id: UUID) -> None:
    """Release reserved stock back to products if order is cancelled or payment fails."""
    stmt = (
        select(InventoryReservation)
        .where(
            InventoryReservation.order_id == order_id,
            InventoryReservation.status == InventoryReservationStatus.RESERVED.value,
        )
        .with_for_update()
    )
    result = await db.scalars(stmt)
    reservations = result.all()

    for res in reservations:
        prod_stmt = select(Product).where(Product.id == res.product_id).with_for_update()
        prod = await db.scalar(prod_stmt)
        if prod:
            prod.stock_quantity += res.qty
        res.status = InventoryReservationStatus.RELEASED.value

    await db.flush()


async def cleanup_expired_reservations(db: AsyncSession) -> int:
    """Release all reservations that have passed their expires_at deadline."""
    now = datetime.now(timezone.utc)
    stmt = (
        select(InventoryReservation)
        .where(
            InventoryReservation.status == InventoryReservationStatus.RESERVED.value,
            InventoryReservation.expires_at <= now,
        )
        .with_for_update()
    )
    result = await db.scalars(stmt)
    expired = result.all()

    count = 0
    for res in expired:
        prod_stmt = select(Product).where(Product.id == res.product_id).with_for_update()
        prod = await db.scalar(prod_stmt)
        if prod:
            prod.stock_quantity += res.qty
        res.status = InventoryReservationStatus.RELEASED.value
        count += 1

    await db.flush()
    return count
