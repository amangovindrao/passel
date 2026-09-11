"""Wallets router — balance + transaction history."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Query

from app.api.dependencies import DbSession, require_role
from app.domain.enums import UserRole, WalletOwnerType
from app.models.entities import User
from app.services.wallet_service import (
    compute_unsettled_balance,
    get_or_create_wallet,
    get_wallet_transactions,
)

router = APIRouter(prefix="/api/v1/wallets", tags=["wallets"])


@router.get("/_role-check", include_in_schema=False)
async def role_check(
    user: Annotated[User, require_role(UserRole.SHOP_OWNER, UserRole.DELIVERY_PARTNER)],
) -> dict[str, str]:
    return {"status": "authorized", "role": user.role}


@router.get("")
async def get_wallet(
    user: Annotated[User, require_role(UserRole.SHOP_OWNER, UserRole.DELIVERY_PARTNER)],
    db: DbSession,
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
) -> dict:
    """Get caller's wallet balance and paginated transaction history."""
    owner_type = (
        WalletOwnerType.SHOP
        if user.role == UserRole.SHOP_OWNER.value
        else WalletOwnerType.DELIVERY_PARTNER
    )
    wallet = await get_or_create_wallet(db, user.id, owner_type)
    balance = await compute_unsettled_balance(db, wallet.id)
    transactions = await get_wallet_transactions(db, wallet.id, limit=limit, offset=offset)

    return {
        "wallet_id": str(wallet.id),
        "balance_paise": balance,
        "owner_type": owner_type.value,
        "transactions": [
            {
                "id": str(t.id),
                "type": t.type,
                "amount_paise": t.amount_paise,
                "order_id": str(t.order_id) if t.order_id else None,
                "settlement_channel": t.settlement_channel,
                "settled_at": t.settled_at.isoformat() if t.settled_at else None,
                "created_at": t.created_at.isoformat() if t.created_at else None,
            }
            for t in transactions
        ],
    }
