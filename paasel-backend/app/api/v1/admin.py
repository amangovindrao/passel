"""Admin router — KYC review for delivery partners and shop owners.

Both onboarding flows deliberately stop at kyc_status='pending' and wait for a
human. This is that human's endpoint. It is also the only place in the system
that writes kyc_status='approved', which is what POST /delivery-partners/online
gates on, so without it nobody can ever start working.
"""

from datetime import UTC, datetime
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Body
from pydantic import BaseModel, Field, model_validator
from sqlalchemy import select

from app.api.dependencies import DbSession, require_role
from app.core.errors import AppError
from app.domain.enums import KycStatus, UserRole
from app.models.entities import (
    DeliveryPartnerProfile,
    Shop,
    ShopOwnerProfile,
    User,
)
from app.services.payouts import (
    ensure_partner_linked_account,
    ensure_shop_linked_account,
)

router = APIRouter(prefix="/api/v1/admin", tags=["admin"])

AdminUser = Annotated[User, require_role(UserRole.ADMIN)]

# Statuses a reviewer can act on. Re-reviewing an approved account would
# silently orphan a live linked account, so it is refused.
_REVIEWABLE = {KycStatus.PENDING.value, KycStatus.SUBMITTED.value}


@router.get("/_role-check", include_in_schema=False)
async def role_check(user: AdminUser) -> dict[str, str]:
    return {"status": "authorized", "role": user.role}


class KycDecisionBody(BaseModel):
    decision: Literal["approved", "rejected"]
    reason: str | None = Field(default=None, max_length=500)

    @model_validator(mode="after")
    def require_reason_when_rejecting(self) -> "KycDecisionBody":
        """A rejection the applicant cannot act on is worse than no answer.

        The apps show this string verbatim on the under-review screen next to a
        resubmit button, so it has to say something useful.
        """
        if self.decision == "rejected" and not (self.reason or "").strip():
            raise ValueError("reason is required when rejecting")
        return self


# --- Review queue ---


@router.get("/kyc/pending")
async def list_pending_kyc(user: AdminUser, db: DbSession) -> dict:
    """Everything awaiting a decision, both sides of the marketplace."""
    partners = (
        await db.execute(
            select(DeliveryPartnerProfile, User.phone)
            .join(User, User.id == DeliveryPartnerProfile.user_id)
            .where(DeliveryPartnerProfile.kyc_status.in_(_REVIEWABLE))
            .order_by(DeliveryPartnerProfile.created_at)
        )
    ).all()

    shops = (
        await db.execute(
            select(ShopOwnerProfile, User.phone)
            .join(User, User.id == ShopOwnerProfile.user_id)
            .where(ShopOwnerProfile.kyc_status.in_(_REVIEWABLE))
            .order_by(ShopOwnerProfile.created_at)
        )
    ).all()

    return {
        "delivery_partners": [
            {
                "user_id": str(p.user_id),
                "name": p.name,
                "phone": phone,
                "kyc_status": p.kyc_status,
                "vehicle_type": p.vehicle_type,
                "vehicle_number": p.vehicle_number,
                "id_proof_url": p.id_proof_url,
                "driving_license_url": p.driving_license_url,
                "has_payout_details": bool(p.bank_account_details),
                "submitted_at": p.updated_at.isoformat() if p.updated_at else None,
            }
            for p, phone in partners
        ],
        "shop_owners": [
            {
                "user_id": str(s.user_id),
                "name": s.name,
                "phone": phone,
                "kyc_status": s.kyc_status,
                "submitted_at": s.updated_at.isoformat() if s.updated_at else None,
            }
            for s, phone in shops
        ],
    }


# --- Decisions ---


@router.post("/delivery-partners/{partner_id}/kyc")
async def review_partner_kyc(
    partner_id: UUID,
    user: AdminUser,
    db: DbSession,
    body: KycDecisionBody = Body(...),
) -> dict:
    """Approve or reject a delivery partner.

    On approval the Razorpay linked account is provisioned — this is the only
    trigger for it. The rider app is watching this row over Realtime, so the
    write itself is what moves them off the under-review screen.
    """
    profile = await db.scalar(
        select(DeliveryPartnerProfile).where(
            DeliveryPartnerProfile.user_id == partner_id
        )
    )
    if profile is None:
        raise AppError(404, "not_found", "Delivery partner profile not found")

    _assert_reviewable(profile.kyc_status)

    if body.decision == "rejected":
        _apply_rejection(profile, body.reason)
        await db.commit()
        return {
            "user_id": str(partner_id),
            "kyc_status": profile.kyc_status,
            "reason": profile.kyc_rejection_reason,
        }

    # A partner with no documents on file was never really submitted.
    if not profile.id_proof_url:
        raise AppError(
            422, "incomplete_kyc", "No ID proof on file — cannot approve"
        )

    partner_user = await db.get(User, partner_id)
    profile.kyc_status = KycStatus.APPROVED.value
    profile.kyc_rejection_reason = None
    profile.kyc_reviewed_at = datetime.now(UTC)

    linked_account_id = await ensure_partner_linked_account(
        db, profile, phone=partner_user.phone if partner_user else ""
    )
    await db.commit()

    return {
        "user_id": str(partner_id),
        "kyc_status": profile.kyc_status,
        "razorpay_linked_account_id": linked_account_id,
        # False means provisioning failed and needs a retry. The approval still
        # stands: the rider can work, they just cannot be paid out yet.
        "payout_ready": linked_account_id is not None,
    }


@router.post("/shop-owners/{owner_id}/kyc")
async def review_shop_owner_kyc(
    owner_id: UUID,
    user: AdminUser,
    db: DbSession,
    body: KycDecisionBody = Body(...),
) -> dict:
    """Approve or reject a shop owner.

    Approval is what makes their shop visible to customers — GET /shops/nearby
    filters on this exact column.
    """
    profile = await db.scalar(
        select(ShopOwnerProfile).where(ShopOwnerProfile.user_id == owner_id)
    )
    if profile is None:
        raise AppError(404, "not_found", "Shop owner profile not found")

    _assert_reviewable(profile.kyc_status)

    if body.decision == "rejected":
        _apply_rejection(profile, body.reason)
        await db.commit()
        return {
            "user_id": str(owner_id),
            "kyc_status": profile.kyc_status,
            "reason": profile.kyc_rejection_reason,
        }

    owner_user = await db.get(User, owner_id)
    shop = await db.scalar(select(Shop).where(Shop.owner_id == owner_id))

    profile.kyc_status = KycStatus.APPROVED.value
    profile.kyc_rejection_reason = None
    profile.kyc_reviewed_at = datetime.now(UTC)

    linked_account_id = await ensure_shop_linked_account(
        db, profile, shop, phone=owner_user.phone if owner_user else ""
    )
    await db.commit()

    return {
        "user_id": str(owner_id),
        "kyc_status": profile.kyc_status,
        "razorpay_linked_account_id": linked_account_id,
        "payout_ready": linked_account_id is not None,
    }


# --- Helpers ---


def _assert_reviewable(status: str) -> None:
    if status in _REVIEWABLE:
        return
    if status == KycStatus.APPROVED.value:
        raise AppError(
            409,
            "already_approved",
            "Already approved — revoking is not supported here",
        )
    raise AppError(
        409, "not_reviewable", f"Nothing to review in state {status}"
    )


def _apply_rejection(profile, reason: str | None) -> None:
    profile.kyc_status = KycStatus.REJECTED.value
    profile.kyc_rejection_reason = (reason or "").strip()
    profile.kyc_reviewed_at = datetime.now(UTC)
