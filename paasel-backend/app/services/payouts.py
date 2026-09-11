"""Razorpay Linked Account provisioning.

A linked account is where money is eventually paid out to, so it is created at
exactly one moment: when a human approves the KYC. Never at submission — an
unverified applicant should not have a payout destination on file — and never
implicitly on first settlement, because a failure there would surface as a
mysterious money problem rather than an onboarding one.
"""

from typing import Any

import structlog
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.entities import DeliveryPartnerProfile, Shop, ShopOwnerProfile
from app.services.razorpay_client import razorpay

log = structlog.get_logger()


def _account_payload(
    *,
    name: str,
    phone: str,
    reference_id: str,
    bank_details: dict[str, Any] | None,
) -> dict[str, Any]:
    """Razorpay Route account body, built from whatever the applicant gave us.

    Bank account and UPI are alternatives; the KYC form accepts either, so only
    the fields actually supplied are sent.
    """
    details = bank_details or {}
    payload: dict[str, Any] = {
        "name": name,
        "email": details.get("email") or f"{reference_id}@partners.paasel.in",
        "contact": phone,
        "type": "route",
        "reference_id": reference_id,
        "legal_business_name": name,
        "business_type": "individual",
    }

    account_number = details.get("account_number")
    ifsc = details.get("ifsc")
    if account_number and ifsc:
        payload["settlements"] = {
            "account_number": account_number,
            "ifsc_code": ifsc,
            "beneficiary_name": details.get("beneficiary_name") or name,
        }
    elif details.get("upi_id"):
        payload["settlements"] = {"vpa": details["upi_id"]}

    return payload


async def ensure_partner_linked_account(
    db: AsyncSession, profile: DeliveryPartnerProfile, phone: str
) -> str | None:
    """Create the partner's linked account if they don't already have one.

    Returns the account id, or None when provisioning failed. Failure is
    deliberately not fatal: the approval itself is a human decision that has
    already been made, and blocking it on a third-party outage would leave the
    rider unable to work for reasons that have nothing to do with them. The
    null id is the signal to retry, and settlement already checks for it.
    """
    if profile.razorpay_linked_account_id:
        return profile.razorpay_linked_account_id

    payload = _account_payload(
        name=profile.name,
        phone=phone,
        reference_id=f"partner_{profile.user_id}",
        bank_details=profile.bank_account_details,
    )

    account_id = await _create(payload, owner="delivery_partner")
    if account_id:
        profile.razorpay_linked_account_id = account_id
        await db.flush()
    return account_id


async def ensure_shop_linked_account(
    db: AsyncSession,
    profile: ShopOwnerProfile,
    shop: Shop | None,
    phone: str,
) -> str | None:
    """Same contract as the partner version, but the id lives on the shop row."""
    if shop is None:
        # Approved before the shop exists. Legitimate: KYC comes first in the
        # shop-owner flow, so there is simply nowhere to hang the id yet.
        return None
    if shop.razorpay_linked_account_id:
        return shop.razorpay_linked_account_id

    payload = _account_payload(
        name=shop.name,
        phone=phone,
        reference_id=f"shop_{shop.id}",
        bank_details=None,
    )

    account_id = await _create(payload, owner="shop")
    if account_id:
        shop.razorpay_linked_account_id = account_id
        await db.flush()
    return account_id


async def _create(payload: dict[str, Any], *, owner: str) -> str | None:
    try:
        account = await razorpay.create_linked_account(payload)
    except Exception as exc:  # noqa: BLE001 — see the note on non-fatal failure
        log.warning(
            "linked_account_creation_failed",
            owner_type=owner,
            reference_id=payload.get("reference_id"),
            error=str(exc),
        )
        return None

    account_id = account.get("id")
    if not account_id:
        log.warning(
            "linked_account_missing_id",
            owner_type=owner,
            reference_id=payload.get("reference_id"),
        )
        return None

    log.info(
        "linked_account_created",
        owner_type=owner,
        reference_id=payload.get("reference_id"),
        account_id=account_id,
    )
    return account_id
