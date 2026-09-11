"""Settlement hook — fires on DELIVERED transition to credit wallets."""

from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.enums import OrderStatus
from app.models.entities import Order
from app.services.order_state_machine import on_transition
from app.services.wallet_service import settle_on_delivery


@on_transition
async def _settle_on_delivered(
    order: Order,
    from_status: OrderStatus,
    to_status: OrderStatus,
    db: AsyncSession,
) -> None:
    """Credit shop + partner wallets when an order is delivered."""
    if to_status == OrderStatus.DELIVERED:
        await settle_on_delivery(db, order)
