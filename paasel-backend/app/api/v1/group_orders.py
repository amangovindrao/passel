"""Group Order Session & Private Cart Privacy Mode API router."""

import random
from datetime import datetime, timedelta, timezone
from typing import Annotated
from uuid import UUID, uuid4

from fastapi import APIRouter, Body, Depends, Path, status
from sqlalchemy import and_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.dependencies import DbSession, get_current_user, require_role
from app.core.errors import AppError
from app.domain.enums import GroupOrderStatus, OrderStatus, OrderType, UserRole
from app.models.entities import (
    CustomerProfile,
    GroupOrderCartItem,
    GroupOrderMember,
    GroupOrderPackage,
    GroupOrderSession,
    Order,
    OrderItem,
    Product,
    Shop,
    User,
)
from app.schemas import (
    CaptainPayRequest,
    GroupMemberPayRequest,
    GroupOrderCartItemIn,
    GroupOrderCartItemOut,
    GroupOrderMemberOut,
    GroupOrderPackageOut,
    GroupOrderProgress,
    GroupOrderSessionCreate,
    GroupOrderSessionOut,
    PackageHandoverRequest,
    PrivacyToggleRequest,
)
from app.services.inventory_service import release_inventory, reserve_inventory
from app.services.wallet_service import (
    debit_wallet_for_order,
    get_or_create_shared_user_wallet,
)

router = APIRouter(prefix="/api/v1/group-orders", tags=["group-orders"])


def format_group_realtime_event(
    session: GroupOrderSession,
    event_type: str,
    member: GroupOrderMember | None = None,
    item_name: str | None = None,
    amount_paise: int | None = None,
) -> dict:
    """Format real-time and notification payloads respecting Private Cart Mode.

    Under Private Cart Mode:
    - Never leaks member names
    - Never leaks product names or images
    - Never leaks financial amounts
    """
    if session.private_cart_mode:
        if event_type in ("item_added", "item_removed", "cart_updated"):
            text = "A member updated their cart."
        elif event_type == "payment_completed":
            text = "A payment was completed."
        elif event_type == "shop_joined":
            text = "A member joined another nearby shop."
        elif event_type == "member_joined":
            text = "A member joined the Group Order."
        else:
            text = "Group order updated."
        return {
            "session_id": str(session.id),
            "event_type": event_type,
            "private_cart_mode": True,
            "message": text,
        }
    else:
        member_name = member.name if member else "A member"
        if event_type == "item_added":
            text = f"{member_name} added {item_name or 'an item'}."
        elif event_type == "item_removed":
            text = f"{member_name} removed an item."
        elif event_type == "payment_completed":
            amount_str = f" ₹{amount_paise // 100}" if amount_paise else ""
            text = f"{member_name}'s{amount_str} order has been paid."
        elif event_type == "member_joined":
            text = f"{member_name} joined the Group Order."
        else:
            text = f"{member_name} updated group order."
        return {
            "session_id": str(session.id),
            "event_type": event_type,
            "private_cart_mode": False,
            "member_id": str(member.id) if member else None,
            "member_name": member_name,
            "message": text,
        }


async def _get_customer_name(db: AsyncSession, user_id: UUID) -> str:
    profile = await db.scalar(select(CustomerProfile).where(CustomerProfile.user_id == user_id))
    return profile.name if profile and profile.name else "Paasel Member"


@router.post("", response_model=GroupOrderSessionOut, status_code=status.HTTP_201_CREATED)
async def create_group_order_session(
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
    body: GroupOrderSessionCreate = Body(...),
) -> GroupOrderSessionOut:
    """Create a new group order session. Creator automatically joins as first member."""
    closes_at = datetime.now(timezone.utc) + timedelta(minutes=body.duration_minutes)
    session = GroupOrderSession(
        creator_id=user.id,
        delivery_address_id=body.delivery_address_id,
        society_name=body.society_name,
        status=GroupOrderStatus.OPEN,
        private_cart_mode=body.private_cart_mode,
        closes_at=closes_at,
    )
    db.add(session)
    await db.flush()

    name = await _get_customer_name(db, user.id)
    member = GroupOrderMember(
        session_id=session.id,
        user_id=user.id,
        name=name,
        is_creator=True,
        status="joined",
    )
    db.add(member)
    await db.commit()

    return await _build_session_out(db, session.id, user.id)


@router.post("/{session_id}/join", response_model=GroupOrderSessionOut)
async def join_group_order_session(
    session_id: UUID,
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
) -> GroupOrderSessionOut:
    """Join an existing group order session."""
    session = await db.get(GroupOrderSession, session_id)
    if not session:
        raise AppError(404, "not_found", "Group order session not found")

    if session.status in (GroupOrderStatus.LOCKED, GroupOrderStatus.PROCESSING, GroupOrderStatus.DELIVERED, GroupOrderStatus.CANCELLED):
        raise AppError(409, "session_locked", f"Cannot join a group order in {session.status} state")

    existing_member = await db.scalar(
        select(GroupOrderMember).where(
            and_(
                GroupOrderMember.session_id == session_id,
                GroupOrderMember.user_id == user.id,
            )
        )
    )
    if not existing_member:
        name = await _get_customer_name(db, user.id)
        new_member = GroupOrderMember(
            session_id=session_id,
            user_id=user.id,
            name=name,
            is_creator=False,
            status="joined",
        )
        db.add(new_member)
        await db.commit()

    return await _build_session_out(db, session_id, user.id)


@router.get("/{session_id}", response_model=GroupOrderSessionOut)
async def get_group_order_session(
    session_id: UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: DbSession,
) -> GroupOrderSessionOut:
    """Get group order details with authoritative backend Private Cart enforcement.

    When private_cart_mode is True:
    - Never returns other members' item details, prices, or payment info.
    - Only returns caller's own cart and anonymized aggregate progress.
    """
    return await _build_session_out(db, session_id, user.id)


@router.patch("/{session_id}/privacy", response_model=dict)
async def toggle_private_cart_mode(
    session_id: UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: DbSession,
    body: PrivacyToggleRequest = Body(...),
) -> dict:
    """Toggle Private Cart Mode ON or OFF for the entire session.

    - Any participating member can turn ON immediately.
    - Turning OFF requires explicit confirmation (confirm_disable=True).
    - Locked sessions cannot change privacy settings.
    """
    session = await db.get(GroupOrderSession, session_id)
    if not session:
        raise AppError(404, "not_found", "Group order session not found")

    # Member check
    member = await db.scalar(
        select(GroupOrderMember).where(
            and_(
                GroupOrderMember.session_id == session_id,
                GroupOrderMember.user_id == user.id,
            )
        )
    )
    if not member:
        raise AppError(403, "forbidden", "Only active members of this group order can change privacy")

    # Lock state check
    if session.status in (GroupOrderStatus.LOCKED, GroupOrderStatus.PROCESSING, GroupOrderStatus.DELIVERED, GroupOrderStatus.CANCELLED):
        raise AppError(409, "privacy_locked", "Privacy settings are locked once order processing begins")

    # Check disable confirmation
    if not body.enable and session.private_cart_mode:
        if not body.confirm_disable:
            raise AppError(
                400,
                "confirmation_required",
                "Disabling Private Cart Mode requires explicit confirmation to protect member privacy",
            )

    session.private_cart_mode = body.enable
    await db.commit()

    return {
        "session_id": str(session.id),
        "private_cart_mode": session.private_cart_mode,
        "message": (
            "Private Cart Mode enabled. All member items and shops are now private."
            if session.private_cart_mode
            else "Private Cart Mode disabled."
        ),
    }


@router.post("/{session_id}/items", response_model=GroupOrderSessionOut)
async def add_or_update_group_cart_item(
    session_id: UUID,
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
    body: GroupOrderCartItemIn = Body(...),
) -> GroupOrderSessionOut:
    """Add or update an item in the caller's cart within the group order."""
    session = await db.get(GroupOrderSession, session_id)
    if not session:
        raise AppError(404, "not_found", "Group order session not found")

    if session.status in (GroupOrderStatus.LOCKED, GroupOrderStatus.PROCESSING, GroupOrderStatus.DELIVERED, GroupOrderStatus.CANCELLED):
        raise AppError(409, "session_locked", "Cannot modify cart in a locked group order")

    member = await db.scalar(
        select(GroupOrderMember).where(
            and_(
                GroupOrderMember.session_id == session_id,
                GroupOrderMember.user_id == user.id,
            )
        )
    )
    if not member:
        raise AppError(403, "forbidden", "You must join this group order first")

    product = await db.get(Product, body.product_id)
    if not product or product.shop_id != body.shop_id:
        raise AppError(404, "not_found", "Product not found in specified shop")

    existing_item = await db.scalar(
        select(GroupOrderCartItem).where(
            and_(
                GroupOrderCartItem.session_id == session_id,
                GroupOrderCartItem.user_id == user.id,
                GroupOrderCartItem.product_id == body.product_id,
            )
        )
    )
    if existing_item:
        if body.qty <= 0:
            await db.delete(existing_item)
        else:
            existing_item.qty = body.qty
            existing_item.price_at_addition_paise = product.price_paise
    else:
        if body.qty > 0:
            item = GroupOrderCartItem(
                session_id=session.id,
                member_id=member.id,
                user_id=user.id,
                shop_id=body.shop_id,
                product_id=body.product_id,
                qty=body.qty,
                price_at_addition_paise=product.price_paise,
            )
            db.add(item)

    await db.commit()
    return await _build_session_out(db, session_id, user.id)


@router.delete("/{session_id}/items/{item_id}", response_model=GroupOrderSessionOut)
async def remove_group_cart_item(
    session_id: UUID,
    item_id: UUID,
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
) -> GroupOrderSessionOut:
    """Remove an item from the caller's group cart."""
    item = await db.get(GroupOrderCartItem, item_id)
    if not item or item.session_id != session_id or item.user_id != user.id:
        raise AppError(404, "not_found", "Cart item not found in your cart")

    await db.delete(item)
    await db.commit()
    return await _build_session_out(db, session_id, user.id)


@router.get("/{session_id}/members/{target_member_id}/cart")
async def get_member_cart(
    session_id: UUID,
    target_member_id: UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: DbSession,
) -> dict:
    """Direct API endpoint for an individual member's cart.

    CRITICAL SECURITY CHECK:
    If Private Cart Mode is ON and the caller is not the target member,
    this endpoint MUST return 403 FORBIDDEN.
    Admin or group creator permissions CANNOT bypass Private Cart Mode.
    """
    session = await db.get(GroupOrderSession, session_id)
    if not session:
        raise AppError(404, "not_found", "Group order session not found")

    target_member = await db.get(GroupOrderMember, target_member_id)
    if not target_member or target_member.session_id != session_id:
        raise AppError(404, "not_found", "Member not found in session")

    # If Private Cart Mode is ON, only the member themselves can view their cart!
    if session.private_cart_mode and target_member.user_id != user.id:
        raise AppError(403, "forbidden", "Private Cart Mode is active. Individual member cart is protected.")

    # Load items
    items_stmt = (
        select(GroupOrderCartItem)
        .options(selectinload(GroupOrderCartItem.product), selectinload(GroupOrderCartItem.shop))
        .where(GroupOrderCartItem.member_id == target_member_id)
    )
    items = list((await db.scalars(items_stmt)).all())

    return {
        "member_id": str(target_member.id),
        "member_name": target_member.name,
        "items": [
            {
                "product_id": str(i.product_id),
                "product_name": i.product.name if i.product else None,
                "shop_id": str(i.shop_id),
                "shop_name": i.shop.name if i.shop else None,
                "qty": i.qty,
                "price_paise": i.price_at_addition_paise,
                "subtotal_paise": i.qty * i.price_at_addition_paise,
            }
            for i in items
        ],
    }


@router.post("/{session_id}/lock", response_model=GroupOrderSessionOut)
async def lock_group_order(
    session_id: UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: DbSession,
) -> GroupOrderSessionOut:
    """Lock the group order to finalize items and prevent further modifications."""
    session = await db.get(GroupOrderSession, session_id)
    if not session:
        raise AppError(404, "not_found", "Group order session not found")

    member = await db.scalar(
        select(GroupOrderMember).where(
            and_(
                GroupOrderMember.session_id == session_id,
                GroupOrderMember.user_id == user.id,
            )
        )
    )
    if not member:
        raise AppError(403, "forbidden", "Only active group members can lock the order")

    session.status = GroupOrderStatus.LOCKED
    await db.commit()
    return await _build_session_out(db, session_id, user.id)


@router.post("/{session_id}/pay", response_model=GroupOrderSessionOut)
async def pay_group_cart(
    session_id: UUID,
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
    body: GroupMemberPayRequest = Body(...),
) -> GroupOrderSessionOut:
    """Process an individual member's payment for their group cart."""
    session = await db.get(GroupOrderSession, session_id)
    if not session:
        raise AppError(404, "not_found", "Group order session not found")

    if session.status in (GroupOrderStatus.DELIVERED, GroupOrderStatus.CANCELLED):
        raise AppError(409, "invalid_session_status", f"Cannot pay for session in {session.status} state")

    member = await db.scalar(
        select(GroupOrderMember).where(
            and_(
                GroupOrderMember.session_id == session_id,
                GroupOrderMember.user_id == user.id,
            )
        )
    )
    if not member:
        raise AppError(403, "forbidden", "You must join this group order first")

    if member.payment_status == "completed":
        return await _build_session_out(db, session_id, user.id)

    items_stmt = (
        select(GroupOrderCartItem)
        .options(selectinload(GroupOrderCartItem.product))
        .where(
            and_(
                GroupOrderCartItem.session_id == session_id,
                GroupOrderCartItem.user_id == user.id,
            )
        )
    )
    items = list((await db.scalars(items_stmt)).all())
    if not items:
        raise AppError(400, "empty_cart", "No items to pay for in your cart")

    member_total = sum(i.qty * i.price_at_addition_paise for i in items)

    # Wallet portion check
    wallet_paid = 0
    if body.wallet_amount_to_use_paise > 0:
        wallet = await get_or_create_shared_user_wallet(db, user.id)
        if wallet.balance_paise < body.wallet_amount_to_use_paise:
            raise AppError(
                422,
                "insufficient_wallet_balance",
                f"Wallet balance ({wallet.balance_paise} paise) is less than requested amount ({body.wallet_amount_to_use_paise} paise)",
            )
        wallet_paid = min(body.wallet_amount_to_use_paise, member_total)

    external_paid = member_total - wallet_paid

    # Group items by shop
    shop_items_map: dict[UUID, list[GroupOrderCartItem]] = {}
    for i in items:
        shop_items_map.setdefault(i.shop_id, []).append(i)

    first_order: Order | None = None
    for shop_id, s_items in shop_items_map.items():
        shop_subtotal = sum(i.qty * i.price_at_addition_paise for i in s_items)
        shop_wallet = int(round(shop_subtotal * (wallet_paid / member_total))) if member_total > 0 else 0
        shop_external = shop_subtotal - shop_wallet

        order = Order(
            id=uuid4(),
            customer_id=user.id,
            shop_id=shop_id,
            status=OrderStatus.PLACED.value,
            order_type=OrderType.GROUP_ORDER.value,
            group_session_id=session.id,
            item_total_paise=shop_subtotal,
            delivery_fee_paise=0,
            payment_mode="wallet" if shop_external == 0 else body.payment_mode,
            payment_status="paid",
            paid_amount_paise=shop_subtotal,
            wallet_amount_used_paise=shop_wallet,
            external_amount_paise=shop_external,
            paid_by_user_id=user.id,
            paid_by_role="member",
            delivery_otp=f"{random.randint(1000, 9999)}",
        )
        db.add(order)
        await db.flush()
        if not first_order:
            first_order = order

        for i in s_items:
            db.add(
                OrderItem(
                    id=uuid4(),
                    order_id=order.id,
                    product_id=i.product_id,
                    qty=i.qty,
                    price_at_order_time_paise=i.price_at_addition_paise,
                )
            )

        # Inventory reservation
        await reserve_inventory(
            db,
            order.id,
            [{"product_id": i.product_id, "quantity": i.qty} for i in s_items],
        )

        # Group order package
        package = GroupOrderPackage(
            id=uuid4(),
            session_id=session.id,
            order_id=order.id,
            shop_id=shop_id,
            member_id=member.id,
            handover_otp=f"{random.randint(1000, 9999)}",
            pickup_status="PENDING",
            delivery_status="NOT_READY",
            handover_status="PENDING",
            handover_type=HandoverType.DIRECT_TO_MEMBER.value,
        )
        db.add(package)

    if wallet_paid > 0 and first_order:
        await debit_wallet_for_order(
            db,
            user_id=user.id,
            order_id=first_order.id,
            amount_paise=wallet_paid,
        )

    member.status = "paid"
    member.payment_status = "completed"
    member.paid_amount_paise = member_total
    member.wallet_amount_used_paise = wallet_paid

    # Check if all members who have items are now paid
    stmt_all = (
        select(GroupOrderMember)
        .options(selectinload(GroupOrderMember.items))
        .where(GroupOrderMember.session_id == session.id)
    )
    all_members = list((await db.scalars(stmt_all)).all())
    members_with_items = [m for m in all_members if (m.items and len(m.items) > 0)]
    if members_with_items and all(m.payment_status == "completed" for m in members_with_items):
        session.payment_complete = True
        session.status = GroupOrderStatus.PROCESSING

    await db.commit()
    return await _build_session_out(db, session_id, user.id)


@router.post("/{session_id}/captain-pay", response_model=GroupOrderSessionOut)
async def captain_pay_remaining(
    session_id: UUID,
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
    body: CaptainPayRequest = Body(...),
) -> GroupOrderSessionOut:
    """Group captain pays for remaining unpaid members' carts on their behalf."""
    session = await db.get(GroupOrderSession, session_id)
    if not session:
        raise AppError(404, "not_found", "Group order session not found")

    if session.creator_id != user.id:
        raise AppError(403, "forbidden", "Only the group captain can pay for all members")

    stmt_all = (
        select(GroupOrderMember)
        .options(selectinload(GroupOrderMember.items).selectinload(GroupOrderCartItem.product))
        .where(GroupOrderMember.session_id == session.id)
    )
    all_members = list((await db.scalars(stmt_all)).all())
    unpaid_members = [
        m for m in all_members if m.items and len(m.items) > 0 and m.payment_status != "completed"
    ]
    if not unpaid_members:
        session.payment_complete = True
        await db.commit()
        return await _build_session_out(db, session_id, user.id)

    grand_remaining = sum(
        sum(i.qty * i.price_at_addition_paise for i in m.items) for m in unpaid_members
    )

    wallet_paid = 0
    if body.wallet_amount_to_use_paise > 0:
        wallet = await get_or_create_shared_user_wallet(db, user.id)
        if wallet.balance_paise < body.wallet_amount_to_use_paise:
            raise AppError(
                422,
                "insufficient_wallet_balance",
                f"Captain wallet balance ({wallet.balance_paise} paise) is less than requested amount ({body.wallet_amount_to_use_paise} paise)",
            )
        wallet_paid = min(body.wallet_amount_to_use_paise, grand_remaining)

    first_order: Order | None = None
    for member in unpaid_members:
        m_items = member.items or []
        m_total = sum(i.qty * i.price_at_addition_paise for i in m_items)
        if m_total <= 0:
            continue

        shop_items_map: dict[UUID, list[GroupOrderCartItem]] = {}
        for i in m_items:
            shop_items_map.setdefault(i.shop_id, []).append(i)

        for shop_id, s_items in shop_items_map.items():
            shop_subtotal = sum(i.qty * i.price_at_addition_paise for i in s_items)
            order = Order(
                id=uuid4(),
                customer_id=member.user_id,  # Ownership stays with the member!
                shop_id=shop_id,
                status=OrderStatus.PLACED.value,
                order_type=OrderType.GROUP_ORDER.value,
                group_session_id=session.id,
                item_total_paise=shop_subtotal,
                delivery_fee_paise=0,
                payment_mode="wallet" if wallet_paid >= grand_remaining else body.payment_mode,
                payment_status="paid",
                paid_amount_paise=shop_subtotal,
                wallet_amount_used_paise=0,
                external_amount_paise=shop_subtotal,
                paid_by_user_id=user.id,  # Captain paid
                paid_by_role="captain",   # Explicit attribution
                delivery_otp=f"{random.randint(1000, 9999)}",
            )
            db.add(order)
            await db.flush()
            if not first_order:
                first_order = order

            for i in s_items:
                db.add(
                    OrderItem(
                        id=uuid4(),
                        order_id=order.id,
                        product_id=i.product_id,
                        qty=i.qty,
                        price_at_order_time_paise=i.price_at_addition_paise,
                    )
                )

            await reserve_inventory(
                db,
                order.id,
                [{"product_id": i.product_id, "quantity": i.qty} for i in s_items],
            )

            package = GroupOrderPackage(
                id=uuid4(),
                session_id=session.id,
                order_id=order.id,
                shop_id=shop_id,
                member_id=member.id,
                handover_otp=f"{random.randint(1000, 9999)}",
                pickup_status="PENDING",
                delivery_status="NOT_READY",
                handover_status="PENDING",
                handover_type=HandoverType.CAPTAIN_HANDOVER.value,
            )
            db.add(package)

        member.status = "paid"
        member.payment_status = "completed"
        member.paid_amount_paise = m_total
        member.wallet_amount_used_paise = 0

    if wallet_paid > 0 and first_order:
        await debit_wallet_for_order(
            db,
            user_id=user.id,
            order_id=first_order.id,
            amount_paise=wallet_paid,
        )

    session.payment_complete = True
    session.status = GroupOrderStatus.PROCESSING
    await db.commit()
    return await _build_session_out(db, session_id, user.id)


@router.post("/{session_id}/handover", response_model=dict)
async def handover_package(
    session_id: UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: DbSession,
    body: PackageHandoverRequest = Body(...),
) -> dict:
    """Rider or captain executes package handover using member verification OTP."""
    session = await db.get(GroupOrderSession, session_id)
    if not session:
        raise AppError(404, "not_found", "Group order session not found")

    if not getattr(session, "payment_complete", False):
        raise AppError(
            422,
            "group_payment_incomplete",
            "Cannot deliver group order until all active member orders are paid",
        )

    pkg = await db.get(GroupOrderPackage, body.package_id)
    if not pkg or pkg.session_id != session_id:
        raise AppError(404, "package_not_found", "Package not found in session")

    if pkg.handover_otp != body.verification_code:
        raise AppError(422, "invalid_code", "Invalid package verification code")

    pkg.delivery_status = "DELIVERED"
    pkg.handover_status = "COMPLETED"

    if pkg.order_id:
        order = await db.get(Order, pkg.order_id)
        if order:
            order.delivery_status = "DELIVERED"

    stmt = select(GroupOrderPackage).where(GroupOrderPackage.session_id == session_id)
    all_pkgs = list((await db.scalars(stmt)).all())
    if all_pkgs and all(p.delivery_status == "DELIVERED" for p in all_pkgs):
        session.status = GroupOrderStatus.DELIVERED

    await db.commit()
    return {
        "session_id": str(session_id),
        "package_id": str(pkg.id),
        "delivery_status": pkg.delivery_status,
        "session_status": session.status,
    }


@router.post("/{session_id}/recheck-deadlines", response_model=GroupOrderSessionOut)
async def recheck_deadlines(
    session_id: UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: DbSession,
) -> GroupOrderSessionOut:
    """Evaluate session deadlines. Releases inventory for unpaid members if deadline expired."""
    session = await db.get(GroupOrderSession, session_id)
    if not session:
        raise AppError(404, "not_found", "Group order session not found")

    now = datetime.now(timezone.utc)
    deadline = session.payment_deadline or session.closes_at
    if deadline and now > deadline:
        stmt = (
            select(GroupOrderMember)
            .options(selectinload(GroupOrderMember.items))
            .where(GroupOrderMember.session_id == session_id)
        )
        members = list((await db.scalars(stmt)).all())
        unpaid = [m for m in members if m.payment_status != "completed"]
        for m in unpaid:
            m.status = "cancelled"
            m.payment_status = "cancelled"

        # Check paid members count
        paid = [m for m in members if m.payment_status == "completed"]
        if paid:
            session.payment_complete = True
            if session.status not in (GroupOrderStatus.DELIVERED, GroupOrderStatus.CANCELLED):
                session.status = GroupOrderStatus.PROCESSING
        else:
            session.status = GroupOrderStatus.CANCELLED

        await db.commit()

    return await _build_session_out(db, session_id, user.id)


async def _build_session_out(
    db: AsyncSession,
    session_id: UUID,
    caller_user_id: UUID,
) -> GroupOrderSessionOut:
    """Construct the authoritative group order session view enforcing Private Cart rules."""
    stmt = (
        select(GroupOrderSession)
        .options(
            selectinload(GroupOrderSession.members).selectinload(GroupOrderMember.items).selectinload(GroupOrderCartItem.product),
            selectinload(GroupOrderSession.members).selectinload(GroupOrderMember.items).selectinload(GroupOrderCartItem.shop),
            selectinload(GroupOrderSession.cart_items).selectinload(GroupOrderCartItem.product),
            selectinload(GroupOrderSession.cart_items).selectinload(GroupOrderCartItem.shop),
            selectinload(GroupOrderSession.packages),
        )
        .where(GroupOrderSession.id == session_id)
    )
    session = await db.scalar(stmt)
    if not session:
        raise AppError(404, "not_found", "Group order session not found")

    members_list = session.members or []
    all_cart_items = session.cart_items or []

    # Calculate aggregate metrics
    member_count = len(members_list)
    unique_shops = {ci.shop_id for ci in all_cart_items}
    shop_count = len(unique_shops)
    carts_ready_count = sum(1 for m in members_list if m.status in ("ready", "paid"))
    payments_completed_count = sum(1 for m in members_list if m.payment_status == "completed" or m.paid_amount_paise > 0)
    delivery_savings_paise = max(0, (member_count - 1) * 2000)

    # Status summary
    if session.status == GroupOrderStatus.LOCKED:
        status_text = f"Order locked • {shop_count} shops preparing"
    elif session.status == GroupOrderStatus.PROCESSING:
        status_text = f"{shop_count} shops preparing orders"
    elif session.status == GroupOrderStatus.DELIVERED:
        status_text = "All group packages delivered"
    else:
        status_text = f"{member_count} members ordering together"

    # Inference protection for group total:
    # If Private Cart Mode is ON, only reveal aggregate total if member_count >= 3
    # to avoid 2-party price inference (Section 18 of specification)
    total_paise = sum(ci.qty * ci.price_at_addition_paise for ci in all_cart_items)
    group_total_paise: int | None = total_paise
    if session.private_cart_mode and member_count < 3:
        group_total_paise = None

    progress = GroupOrderProgress(
        member_count=member_count,
        shop_count=shop_count,
        carts_ready_count=carts_ready_count,
        payments_completed_count=payments_completed_count,
        status_text=status_text,
        delivery_savings_paise=delivery_savings_paise,
        group_total_paise=group_total_paise,
    )

    # Build member representations
    caller_cart_items_out: list[GroupOrderCartItemOut] = []
    caller_subtotal = 0
    members_out: list[GroupOrderMemberOut] = []

    for m in members_list:
        is_caller = (m.user_id == caller_user_id)
        m_items = m.items or []
        m_subtotal = sum(i.qty * i.price_at_addition_paise for i in m_items)

        if is_caller:
            caller_subtotal = m_subtotal
            caller_cart_items_out = [
                GroupOrderCartItemOut(
                    id=i.id,
                    shop_id=i.shop_id,
                    shop_name=i.shop.name if i.shop else None,
                    product_id=i.product_id,
                    product_name=i.product.name if i.product else None,
                    qty=i.qty,
                    price_at_addition_paise=i.price_at_addition_paise,
                    subtotal_paise=i.qty * i.price_at_addition_paise,
                )
                for i in m_items
            ]

        # PRIVACY ENFORCEMENT RULE:
        # If private_cart_mode is active, scrub items, shop info, and financial info for non-caller members
        if session.private_cart_mode and not is_caller:
            members_out.append(
                GroupOrderMemberOut(
                    id=m.id,
                    user_id=m.user_id,
                    name=m.name,
                    is_creator=m.is_creator,
                    status=m.status,
                    payment_status=m.payment_status,
                    items=[],  # SCRUBBED
                    subtotal_paise=None,  # SCRUBBED
                    paid_amount_paise=None,  # SCRUBBED
                    wallet_amount_used_paise=None,  # SCRUBBED
                )
            )
        else:
            # Full details visible (either private mode is OFF, or this is the caller's own member object)
            members_out.append(
                GroupOrderMemberOut(
                    id=m.id,
                    user_id=m.user_id,
                    name=m.name,
                    is_creator=m.is_creator,
                    status=m.status,
                    payment_status=m.payment_status,
                    items=[
                        GroupOrderCartItemOut(
                            id=i.id,
                            shop_id=i.shop_id,
                            shop_name=i.shop.name if i.shop else None,
                            product_id=i.product_id,
                            product_name=i.product.name if i.product else None,
                            qty=i.qty,
                            price_at_addition_paise=i.price_at_addition_paise,
                            subtotal_paise=i.qty * i.price_at_addition_paise,
                        )
                        for i in m_items
                    ],
                    subtotal_paise=m_subtotal,
                    paid_amount_paise=m.paid_amount_paise,
                    wallet_amount_used_paise=m.wallet_amount_used_paise,
                )
            )

    raw_packages = session.packages or []
    packages_out: list[GroupOrderPackageOut] = []
    for p in raw_packages:
        can_see_code = (p.member_id == caller_user_id or session.creator_id == caller_user_id)
        otp_val = p.handover_otp if can_see_code else "****"
        packages_out.append(
            GroupOrderPackageOut(
                id=p.id,
                session_id=p.session_id,
                order_id=p.order_id,
                shop_id=p.shop_id,
                member_id=p.member_id,
                handover_otp=otp_val,
                pickup_status=p.pickup_status,
                delivery_status=p.delivery_status,
                handover_status=p.handover_status,
                handover_type=p.handover_type,
            )
        )

    return GroupOrderSessionOut(
        id=session.id,
        creator_id=session.creator_id,
        delivery_address_id=session.delivery_address_id,
        society_name=session.society_name,
        status=session.status,
        private_cart_mode=session.private_cart_mode,
        closes_at=session.closes_at,
        payment_complete=getattr(session, "payment_complete", False),
        progress=progress,
        members=members_out,
        my_cart=caller_cart_items_out,
        my_subtotal_paise=caller_subtotal,
        packages=packages_out,
    )
