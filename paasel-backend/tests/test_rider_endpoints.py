"""Delivery-partner endpoints over HTTP, and the KYC review that gates them.

These go through the app rather than calling services directly, because the
things worth pinning down here are the status codes and messages the rider app
actually branches on: the 403 before approval, the 409 mid-delivery, and the
approval that turns one into the other.
"""

from datetime import UTC, datetime
from uuid import uuid4

from sqlalchemy import select

from app.domain.enums import AssignmentStatus, KycStatus, OrderStatus, UserRole
from app.models.entities import DeliveryPartnerProfile, Order, Shop, User
from tests.factories import (
    make_assignment,
    make_order,
    make_partner,
    make_shop,
    make_user,
)

ONLINE = "/api/v1/delivery-partners/online"
ME = "/api/v1/delivery-partners/me"


async def _profile(db, partner_id) -> DeliveryPartnerProfile:
    return await db.scalar(
        select(DeliveryPartnerProfile).where(
            DeliveryPartnerProfile.user_id == partner_id
        )
    )


async def _approve(db, partner_id) -> None:
    profile = await _profile(db, partner_id)
    profile.kyc_status = KycStatus.APPROVED.value
    await db.flush()


# --- POST /online : the 403 gate ---


async def test_online_refused_until_kyc_approved(api, db_session):
    """A pending partner cannot make themselves available."""
    partner = await make_partner(
        db_session, lng=77.5990, is_online=False,
        kyc_status=KycStatus.PENDING.value,
    )

    resp = await api.as_user(partner).post(ONLINE, json={"is_online": True})

    assert resp.status_code == 403
    assert resp.json()["error"]["code"] == "kyc_not_approved"
    assert await _profile(db_session, partner.id) is not None
    assert (await _profile(db_session, partner.id)).is_online is False


async def test_online_succeeds_once_approved(api, db_session):
    partner = await make_partner(db_session, lng=77.5990, is_online=False)
    await _approve(db_session, partner.id)

    resp = await api.as_user(partner).post(ONLINE, json={"is_online": True})

    assert resp.status_code == 200
    assert resp.json() == {"is_online": True}
    assert (await _profile(db_session, partner.id)).is_online is True


# --- POST /online : the 409 mid-delivery, and its release ---


async def test_offline_returns_409_while_a_delivery_is_in_progress(
    api, db_session
):
    """The spec'd case: accepted assignment, order not yet delivered."""
    shop = await make_shop(db_session)
    partner = await make_partner(db_session, lng=77.5990)
    await _approve(db_session, partner.id)

    order = await make_order(
        db_session, shop=shop, status=OrderStatus.OUT_FOR_DELIVERY,
        with_address=True,
    )
    await make_assignment(db_session, order, partner, accepted=True)

    resp = await api.as_user(partner).post(ONLINE, json={"is_online": False})

    assert resp.status_code == 409
    body = resp.json()["error"]
    assert body["code"] == "delivery_in_progress"
    assert body["message"] == "Finish your current delivery first"
    # And crucially the server did not change its mind either.
    assert (await _profile(db_session, partner.id)).is_online is True


async def test_offline_succeeds_once_that_order_is_delivered(api, db_session):
    """Same partner, same assignment — only the order status moves."""
    shop = await make_shop(db_session)
    partner = await make_partner(db_session, lng=77.5990)
    await _approve(db_session, partner.id)

    order = await make_order(
        db_session, shop=shop, status=OrderStatus.OUT_FOR_DELIVERY,
        with_address=True,
    )
    await make_assignment(db_session, order, partner, accepted=True)

    blocked = await api.as_user(partner).post(ONLINE, json={"is_online": False})
    assert blocked.status_code == 409

    order.status = OrderStatus.DELIVERED.value
    await db_session.flush()

    allowed = await api.as_user(partner).post(ONLINE, json={"is_online": False})

    assert allowed.status_code == 200
    assert allowed.json()["is_online"] is False
    assert (await _profile(db_session, partner.id)).is_online is False


async def test_offline_allowed_with_an_unanswered_offer(api, db_session):
    """An offer they never answered must not trap them online."""
    shop = await make_shop(db_session)
    partner = await make_partner(db_session, lng=77.5990)
    await _approve(db_session, partner.id)

    order = await make_order(db_session, shop=shop)
    await make_assignment(
        db_session, order, partner, status=AssignmentStatus.OFFERED.value
    )

    resp = await api.as_user(partner).post(ONLINE, json={"is_online": False})

    assert resp.status_code == 200
    assert resp.json()["is_online"] is False
    # The offer is handed back to the timeout path so it can find someone else.
    assert resp.json()["released_offer"] is True


async def test_accepting_an_offer_blocks_going_offline(api, db_session):
    """The 409 has to survive a real accept, not just a hand-built row.

    The other offline tests construct an already-accepted assignment directly,
    which passes even when the accept endpoint forgets to move the status — and
    that gap let a partner accept a delivery and then go straight offline.
    """
    shop = await make_shop(db_session)
    partner = await make_partner(db_session, lng=77.5990)
    await _approve(db_session, partner.id)
    await api.as_user(partner).post(ONLINE, json={"is_online": True})

    order = await make_order(
        db_session,
        shop=shop,
        status=OrderStatus.READY_FOR_PICKUP,
        with_address=True,
    )
    assignment = await make_assignment(
        db_session, order, partner, status=AssignmentStatus.OFFERED.value
    )

    accepted = await api.as_user(partner).post(
        f"/api/v1/orders/assignments/{assignment.id}/accept"
    )
    assert accepted.status_code == 200

    resp = await api.as_user(partner).post(ONLINE, json={"is_online": False})

    assert resp.status_code == 409
    assert resp.json()["error"]["code"] == "delivery_in_progress"
    assert (await _profile(db_session, partner.id)).is_online is True


async def test_an_expired_offer_cannot_be_accepted(api, db_session):
    """Whoever it went to next now owns it; two partners cannot both hold it."""
    shop = await make_shop(db_session)
    partner = await make_partner(db_session, lng=77.5990)
    order = await make_order(
        db_session, shop=shop, status=OrderStatus.READY_FOR_PICKUP
    )
    assignment = await make_assignment(
        db_session, order, partner, status=AssignmentStatus.EXPIRED.value
    )

    resp = await api.as_user(partner).post(
        f"/api/v1/orders/assignments/{assignment.id}/accept"
    )

    assert resp.status_code == 409
    assert resp.json()["error"]["code"] == "offer_closed"


# --- GET /me ---


async def test_me_reports_rejection_reason(api, db_session):
    partner = await make_partner(db_session, lng=77.5990, is_online=False)
    profile = await _profile(db_session, partner.id)
    profile.kyc_status = KycStatus.REJECTED.value
    profile.kyc_rejection_reason = "ID proof is unreadable"
    await db_session.flush()

    body = (await api.as_user(partner).get(ME)).json()

    assert body["kyc_status"] == "rejected"
    assert body["kyc_rejection_reason"] == "ID proof is unreadable"


async def test_me_counts_only_todays_completed_deliveries(api, db_session):
    shop = await make_shop(db_session)
    partner = await make_partner(db_session, lng=77.5990)

    for status in (
        OrderStatus.DELIVERED,
        OrderStatus.COMPLETED,
        OrderStatus.OUT_FOR_DELIVERY,
    ):
        order = await make_order(db_session, shop=shop, status=status)
        await make_assignment(db_session, order, partner, accepted=True)

    body = (await api.as_user(partner).get(ME)).json()

    # Delivered + completed count; the one still out for delivery does not.
    assert body["completed_today"] == 2
    # It is a count, never money.
    assert "earnings" not in body
    assert not any("paise" in key for key in body)


# --- Admin KYC review ---


async def test_admin_approval_flips_status_and_provisions_payout(
    api, db_session, monkeypatch
):
    """Approval is the only trigger for the Razorpay linked account."""
    created: list[dict] = []

    async def fake_create(details):
        created.append(details)
        return {"id": "acc_TEST123"}

    monkeypatch.setattr(
        "app.services.payouts.razorpay.create_linked_account", fake_create
    )

    partner = await make_partner(
        db_session, lng=77.5990, is_online=False,
        kyc_status=KycStatus.PENDING.value,
    )
    profile = await _profile(db_session, partner.id)
    profile.id_proof_url = "https://storage.test/id.jpg"
    profile.bank_account_details = {
        "account_number": "123456789",
        "ifsc": "SBIN0001234",
    }
    await db_session.flush()

    admin = await make_user(db_session, UserRole.ADMIN.value)
    resp = await api.as_user(admin).post(
        f"/api/v1/admin/delivery-partners/{partner.id}/kyc",
        json={"decision": "approved"},
    )

    assert resp.status_code == 200
    body = resp.json()
    assert body["kyc_status"] == "approved"
    assert body["razorpay_linked_account_id"] == "acc_TEST123"
    assert body["payout_ready"] is True

    refreshed = await _profile(db_session, partner.id)
    assert refreshed.kyc_status == KycStatus.APPROVED.value
    assert refreshed.razorpay_linked_account_id == "acc_TEST123"
    assert refreshed.kyc_reviewed_at is not None

    assert len(created) == 1, "exactly one linked account"
    assert created[0]["reference_id"] == f"partner_{partner.id}"
    assert created[0]["settlements"]["ifsc_code"] == "SBIN0001234"


async def test_approval_survives_a_razorpay_outage(api, db_session, monkeypatch):
    """A payout-provider failure must not block a human's approval decision."""

    async def boom(details):
        raise RuntimeError("razorpay unavailable")

    monkeypatch.setattr(
        "app.services.payouts.razorpay.create_linked_account", boom
    )

    partner = await make_partner(
        db_session, lng=77.5990, kyc_status=KycStatus.PENDING.value
    )
    profile = await _profile(db_session, partner.id)
    profile.id_proof_url = "https://storage.test/id.jpg"
    await db_session.flush()

    admin = await make_user(db_session, UserRole.ADMIN.value)
    resp = await api.as_user(admin).post(
        f"/api/v1/admin/delivery-partners/{partner.id}/kyc",
        json={"decision": "approved"},
    )

    assert resp.status_code == 200
    assert resp.json()["kyc_status"] == "approved"
    # Flagged as not payable yet, so it can be retried.
    assert resp.json()["payout_ready"] is False
    assert (await _profile(db_session, partner.id)).kyc_status == "approved"


async def test_admin_rejection_records_a_reason(api, db_session):
    partner = await make_partner(
        db_session, lng=77.5990, kyc_status=KycStatus.PENDING.value
    )
    admin = await make_user(db_session, UserRole.ADMIN.value)

    resp = await api.as_user(admin).post(
        f"/api/v1/admin/delivery-partners/{partner.id}/kyc",
        json={"decision": "rejected", "reason": "Licence has expired"},
    )

    assert resp.status_code == 200
    assert resp.json()["reason"] == "Licence has expired"
    refreshed = await _profile(db_session, partner.id)
    assert refreshed.kyc_status == KycStatus.REJECTED.value
    assert refreshed.kyc_rejection_reason == "Licence has expired"


async def test_rejection_without_a_reason_is_refused(api, db_session):
    """A rejection the applicant cannot act on is not acceptable."""
    partner = await make_partner(
        db_session, lng=77.5990, kyc_status=KycStatus.PENDING.value
    )
    admin = await make_user(db_session, UserRole.ADMIN.value)

    resp = await api.as_user(admin).post(
        f"/api/v1/admin/delivery-partners/{partner.id}/kyc",
        json={"decision": "rejected"},
    )

    assert resp.status_code == 422


async def test_approval_requires_documents_on_file(api, db_session):
    partner = await make_partner(
        db_session, lng=77.5990, kyc_status=KycStatus.PENDING.value
    )
    admin = await make_user(db_session, UserRole.ADMIN.value)

    resp = await api.as_user(admin).post(
        f"/api/v1/admin/delivery-partners/{partner.id}/kyc",
        json={"decision": "approved"},
    )

    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "incomplete_kyc"


async def test_reapproving_is_refused(api, db_session, monkeypatch):
    """Re-approving would orphan the existing linked account."""

    async def fake_create(details):
        return {"id": "acc_ONCE"}

    monkeypatch.setattr(
        "app.services.payouts.razorpay.create_linked_account", fake_create
    )

    partner = await make_partner(
        db_session, lng=77.5990, kyc_status=KycStatus.PENDING.value
    )
    profile = await _profile(db_session, partner.id)
    profile.id_proof_url = "https://storage.test/id.jpg"
    await db_session.flush()

    admin = await make_user(db_session, UserRole.ADMIN.value)
    path = f"/api/v1/admin/delivery-partners/{partner.id}/kyc"

    first = await api.as_user(admin).post(path, json={"decision": "approved"})
    assert first.status_code == 200

    second = await api.as_user(admin).post(path, json={"decision": "approved"})
    assert second.status_code == 409
    assert second.json()["error"]["code"] == "already_approved"


async def test_pending_queue_lists_the_submission(api, db_session):
    partner = await make_partner(
        db_session, lng=77.5990, kyc_status=KycStatus.PENDING.value
    )
    profile = await _profile(db_session, partner.id)
    profile.id_proof_url = "https://storage.test/id.jpg"
    profile.bank_account_details = {"upi_id": "rider@bank"}
    await db_session.flush()

    admin = await make_user(db_session, UserRole.ADMIN.value)
    body = (await api.as_user(admin).get("/api/v1/admin/kyc/pending")).json()

    entry = next(
        p for p in body["delivery_partners"]
        if p["user_id"] == str(partner.id)
    )
    assert entry["kyc_status"] == "pending"
    assert entry["id_proof_url"] == "https://storage.test/id.jpg"
    # The reviewer is told payout details exist without being shown them.
    assert entry["has_payout_details"] is True
    assert "bank_account_details" not in entry


async def test_kyc_review_is_admin_only(api, db_session):
    partner = await make_partner(
        db_session, lng=77.5990, kyc_status=KycStatus.PENDING.value
    )

    resp = await api.as_user(partner).post(
        f"/api/v1/admin/delivery-partners/{partner.id}/kyc",
        json={"decision": "approved"},
    )

    assert resp.status_code == 403


# --- End-to-end: the deliverable's own sentence ---


async def test_pending_to_approved_to_online(api, db_session, monkeypatch):
    """The spec's headline claim, walked in one test.

    A partner submits, cannot go online, gets approved, and then can.
    """

    async def fake_create(details):
        return {"id": "acc_FLOW"}

    monkeypatch.setattr(
        "app.services.payouts.razorpay.create_linked_account", fake_create
    )

    partner = await make_partner(
        db_session, lng=77.5990, is_online=False,
        kyc_status=KycStatus.PENDING.value,
    )
    profile = await _profile(db_session, partner.id)
    profile.id_proof_url = "https://storage.test/id.jpg"
    await db_session.flush()

    blocked = await api.as_user(partner).post(ONLINE, json={"is_online": True})
    assert blocked.status_code == 403

    admin = await make_user(db_session, UserRole.ADMIN.value)
    approved = await api.as_user(admin).post(
        f"/api/v1/admin/delivery-partners/{partner.id}/kyc",
        json={"decision": "approved"},
    )
    assert approved.status_code == 200

    now_allowed = await api.as_user(partner).post(
        ONLINE, json={"is_online": True}
    )
    assert now_allowed.status_code == 200
    assert (await _profile(db_session, partner.id)).is_online is True
