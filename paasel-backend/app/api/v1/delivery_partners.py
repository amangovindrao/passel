"""Delivery partner profile, KYC, availability and location reporting."""

from datetime import UTC, datetime
from typing import Annotated, Any
from uuid import UUID

from fastapi import APIRouter, Body
from pydantic import BaseModel, Field, model_validator
from sqlalchemy import func, select, text

from app.api.dependencies import DbSession, require_role
from app.core.errors import AppError
from app.domain.enums import (
    KycStatus,
    OfferType,
    OrderStatus,
    UserRole,
    VehicleType,
)
from app.models.entities import (
    DeliveryAssignment,
    DeliveryPartnerProfile,
    Order,
    OrderItem,
    Shop,
    User,
)
from app.services.batch_offers import (
    active_accepted_assignment,
    outstanding_offer,
)
from app.services.partner_matching import (
    BATCH_OFFER_WINDOW_SECONDS,
    FRESH_OFFER_WINDOW_SECONDS,
)

router = APIRouter(prefix="/api/v1/delivery-partners", tags=["delivery-partners"])

RiderUser = Annotated[User, require_role(UserRole.DELIVERY_PARTNER)]


# --- Schemas ---


class PartnerProfileBody(BaseModel):
    name: str = Field(min_length=2, max_length=120)


class KycBody(BaseModel):
    id_proof_url: str
    vehicle_type: VehicleType
    vehicle_number: str | None = None
    driving_license_url: str | None = None
    bank_account_details: dict[str, Any]

    @model_validator(mode="after")
    def check_vehicle_documents(self) -> "KycBody":
        """A bicycle has no plate and needs no licence; a bike/scooter has both.

        Rejecting the extra fields for a bicycle rather than ignoring them keeps
        the stored record unambiguous — a vehicle_number on a bicycle row would
        only ever be someone else's data or a client bug.
        """
        if self.vehicle_type.requires_registration:
            missing = [
                field
                for field, value in (
                    ("vehicle_number", self.vehicle_number),
                    ("driving_license_url", self.driving_license_url),
                )
                if not value
            ]
            if missing:
                raise ValueError(
                    f"{self.vehicle_type.value} requires: {', '.join(missing)}"
                )
        else:
            provided = [
                field
                for field, value in (
                    ("vehicle_number", self.vehicle_number),
                    ("driving_license_url", self.driving_license_url),
                )
                if value
            ]
            if provided:
                raise ValueError(
                    f"bicycle must not include: {', '.join(provided)}"
                )
        return self


class OnlineBody(BaseModel):
    is_online: bool


class LocationBody(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)


# --- Profile ---


@router.post("/profile")
async def create_partner_profile(
    user: RiderUser,
    db: DbSession,
    body: PartnerProfileBody = Body(...),
) -> dict:
    """Create or rename the partner's profile. Vehicle comes later, at KYC."""
    profile = await _profile_or_none(db, user)
    if profile:
        profile.name = body.name
    else:
        db.add(DeliveryPartnerProfile(user_id=user.id, name=body.name))
    await db.commit()
    return {"status": "ok", "name": body.name}


@router.post("/kyc")
async def submit_partner_kyc(
    user: RiderUser,
    db: DbSession,
    body: KycBody = Body(...),
) -> dict:
    """Submit documents for review. Sets kyc_status='pending'.

    The Razorpay linked account is deliberately NOT created here. It is created
    only once a human approves the KYC, same rule as the shop side — an
    unverified partner should not have a payout destination on file.
    """
    profile = await _profile_or_none(db, user)
    if not profile:
        raise AppError(404, "no_profile", "Create profile first")

    if profile.kyc_status == KycStatus.APPROVED.value:
        raise AppError(
            409,
            "already_approved",
            "Your account is already verified",
        )

    profile.id_proof_url = body.id_proof_url
    profile.vehicle_type = body.vehicle_type.value
    profile.vehicle_number = body.vehicle_number
    profile.driving_license_url = body.driving_license_url
    profile.bank_account_details = body.bank_account_details
    profile.kyc_status = KycStatus.PENDING.value
    # A resubmission answers the previous rejection, so the stale reason goes.
    profile.kyc_rejection_reason = None
    profile.kyc_reviewed_at = None
    await db.commit()

    return {"status": "pending", "kyc_status": KycStatus.PENDING.value}


@router.get("/me")
async def get_me(user: RiderUser, db: DbSession) -> dict:
    """Profile, verification state, availability, and today's delivery count.

    The count is a plain tally of completed deliveries, not an earnings figure.
    Money is reconciled in the wallet; a partial number here would be worse
    than none at all.
    """
    profile = await _profile_or_none(db, user)
    if not profile:
        return {"exists": False, "kyc_status": None, "is_online": False}

    day_start = datetime.now(UTC).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    completed_today = await db.scalar(
        select(func.count())
        .select_from(DeliveryAssignment)
        .join(Order, Order.id == DeliveryAssignment.order_id)
        .where(
            DeliveryAssignment.partner_id == user.id,
            Order.status.in_([
                OrderStatus.DELIVERED.value,
                OrderStatus.COMPLETED.value,
            ]),
            Order.updated_at >= day_start,
        )
    )

    return {
        "exists": True,
        "name": profile.name,
        "kyc_status": profile.kyc_status,
        # Only populated on rejection. The app shows it verbatim above the
        # resubmit button, so a rejected applicant knows what to fix.
        "kyc_rejection_reason": profile.kyc_rejection_reason,
        "vehicle_type": profile.vehicle_type,
        "vehicle_number": profile.vehicle_number,
        "is_online": profile.is_online,
        "completed_today": int(completed_today or 0),
    }


# --- Offers ---


@router.get("/me/offer")
async def get_current_offer(user: RiderUser, db: DbSession) -> dict:
    """The offer this partner has not answered yet, or null.

    Push is the right channel for reaching a backgrounded phone, but it is not
    the only one that has to work: a foregrounded app whose Firebase setup is
    missing, whose token has rotated, or that was simply launched after the
    offer was made would otherwise never find out an offer exists at all. This
    is the pull side of the same fact, and it is what makes the offer flow
    self-healing rather than dependent on one delivery attempt landing.

    `window_seconds` is the time *remaining*, not the original window. A client
    polling at second 30 that then counted down from the full 35 would show
    five seconds which do not exist, and the accept at the end of them would
    fail.
    """
    offer = await outstanding_offer(db, user.id)
    if offer is None:
        return {"offer": None}

    window = offer.window_seconds or (
        BATCH_OFFER_WINDOW_SECONDS
        if offer.offer_type == OfferType.BATCH_DETOUR.value
        else FRESH_OFFER_WINDOW_SECONDS
    )
    elapsed = (datetime.now(UTC) - offer.assigned_at).total_seconds()
    remaining = int(window - elapsed)
    if remaining <= 0:
        # The window has closed; the timeout task will clear the row shortly.
        # Handing this to a client would only ever produce a failed accept.
        return {"offer": None}

    order = await db.get(Order, offer.order_id)
    if order is None:
        return {"offer": None}

    shop = await db.get(Shop, order.shop_id)
    item_count = await db.scalar(
        select(func.coalesce(func.sum(OrderItem.qty), 0)).where(
            OrderItem.order_id == order.id
        )
    )
    # Straight-line, matching what the search radius is measured with. The
    # rider only needs to know roughly how far the pickup is before answering.
    distance_m = await db.scalar(
        text("""
            SELECT ST_Distance(ll.location, s.location)
            FROM live_locations ll, shops s
            WHERE ll.partner_id = :partner_id AND s.id = :shop_id
        """),
        {"partner_id": str(user.id), "shop_id": str(order.shop_id)},
    )

    return {
        "offer": {
            "assignment_id": str(offer.id),
            "order_id": str(order.id),
            "offer_type": offer.offer_type,
            "shop_name": shop.name if shop else "Shop",
            "item_count": int(item_count or 0),
            "delivery_fee_paise": order.delivery_fee_paise,
            "distance_to_shop_m": (
                int(distance_m) if distance_m is not None else None
            ),
            "detour_meters": offer.detour_meters,
            "window_seconds": remaining,
        }
    }


# --- Availability ---


@router.post("/online")
async def set_online(
    user: RiderUser,
    db: DbSession,
    body: OnlineBody = Body(...),
) -> dict:
    """Go online or offline.

    Going online requires an approved KYC. Going offline is refused while a
    delivery is in progress, but an offer the partner simply hasn't answered
    never blocks them — that offer is released so it can find someone else.
    """
    profile = await _profile_or_none(db, user)
    if not profile:
        raise AppError(404, "no_profile", "Create profile first")

    if body.is_online:
        if profile.kyc_status != KycStatus.APPROVED.value:
            raise AppError(
                403,
                "kyc_not_approved",
                "Your account is still being verified",
            )
        profile.is_online = True
        await db.commit()
        return {"is_online": True}

    # --- Going offline ---
    active = await active_accepted_assignment(db, user.id)
    if active:
        raise AppError(
            409,
            "delivery_in_progress",
            "Finish your current delivery first",
        )

    released = await _release_outstanding_offer(db, user.id)

    profile.is_online = False
    await db.commit()
    return {"is_online": False, "released_offer": released}


@router.post("/location")
async def report_location(
    user: RiderUser,
    db: DbSession,
    body: LocationBody = Body(...),
) -> dict:
    """Upsert the partner's live location and refresh its timestamp.

    Called every 5-10s for as long as the partner is online, with or without an
    active order. Matching treats a partner with no recent ping as unreachable,
    so this is what keeps them visible to dispatch at all.
    """
    point = f"SRID=4326;POINT({body.lng} {body.lat})"
    now = datetime.now(UTC)

    await db.execute(
        text("""
            INSERT INTO live_locations (partner_id, location, updated_at, created_at)
            VALUES (:partner_id, ST_GeogFromText(:point), :now, :now)
            ON CONFLICT (partner_id) DO UPDATE
            SET location = ST_GeogFromText(:point),
                updated_at = :now
        """),
        {"partner_id": str(user.id), "point": point, "now": now},
    )

    # Mirror onto the profile so a partner row is self-contained for admin views.
    profile = await _profile_or_none(db, user)
    if profile:
        profile.current_location = point

    await db.commit()
    return {"status": "ok", "updated_at": now.isoformat()}


# --- Helpers ---


async def _profile_or_none(
    db: DbSession, user: User
) -> DeliveryPartnerProfile | None:
    return await db.scalar(
        select(DeliveryPartnerProfile).where(
            DeliveryPartnerProfile.user_id == user.id
        )
    )


async def _release_outstanding_offer(db: DbSession, partner_id: UUID) -> bool:
    """Hand an unanswered offer straight to the timeout path, now.

    Rather than expiring it here and duplicating the cascade logic, the existing
    timeout task is re-enqueued with no delay. It re-reads the row, sees it is
    still merely offered, and does exactly what it would have done at the end of
    the window — one code path, one behaviour.
    """
    offer = await outstanding_offer(db, partner_id)
    if offer is None:
        return False

    from app.services.batch_offers import revoke_timeout
    from app.workers.tasks import (
        assignment_timeout_check,
        batch_offer_timeout_check,
    )

    revoke_timeout(offer)

    if offer.offer_type == OfferType.BATCH_DETOUR.value:
        batch_offer_timeout_check.apply_async(
            args=[str(offer.id), str(offer.order_id)], countdown=0
        )
    else:
        assignment_timeout_check.apply_async(
            args=[str(offer.id), str(offer.order_id), offer.cascade_count],
            countdown=0,
        )
    return True
