"""SQLAlchemy ORM models — exact Paasel domain schema."""

from datetime import datetime
from uuid import UUID, uuid4

from geoalchemy2 import Geography
from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    SmallInteger,
    String,
    Text,
    func,
)
from sqlalchemy.dialects.postgresql import ARRAY, JSONB, UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.domain.enums import (
    DisputeStatus,
    ItemAvailability,
    KycStatus,
    OfferType,
    OrderStatus,
    PaymentMode,
    PaymentStatus,
    PhotoCapturedBy,
    PhotoStage,
    RatedEntityType,
    RefundStatus,
    StockStatus,
    SubscriptionStatus,
    UserRole,
    VehicleType,
    WalletOwnerType,
    WalletTxnType,
)


# ---------------------------------------------------------------------------
# Mixin
# ---------------------------------------------------------------------------


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )


# ---------------------------------------------------------------------------
# Users & Profiles
# ---------------------------------------------------------------------------


class User(TimestampMixin, Base):
    __tablename__ = "users"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    phone: Mapped[str] = mapped_column(String(20), unique=True, nullable=False)
    role: Mapped[UserRole] = mapped_column(String(20), nullable=False, index=True)


class CustomerProfile(TimestampMixin, Base):
    __tablename__ = "customer_profiles"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)


class ShopOwnerProfile(TimestampMixin, Base):
    __tablename__ = "shop_owner_profiles"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    kyc_status: Mapped[KycStatus] = mapped_column(
        String(20), nullable=False, server_default="pending", index=True
    )
    # Only set when kyc_status is 'rejected' — the applicant needs to know what
    # to fix before resubmitting.
    kyc_rejection_reason: Mapped[str | None] = mapped_column(Text)
    kyc_reviewed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True)
    )


class DeliveryPartnerProfile(TimestampMixin, Base):
    __tablename__ = "delivery_partner_profiles"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    kyc_status: Mapped[KycStatus] = mapped_column(
        String(20), nullable=False, server_default="pending", index=True
    )
    kyc_rejection_reason: Mapped[str | None] = mapped_column(Text)
    kyc_reviewed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True)
    )
    # Nullable until KYC is submitted — POST /delivery-partners/profile only
    # carries the partner's name, the vehicle is chosen on the KYC step.
    vehicle_type: Mapped[VehicleType | None] = mapped_column(String(20))
    is_online: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    current_location: Mapped[object | None] = mapped_column(
        Geography("POINT", srid=4326, spatial_index=False)
    )
    razorpay_linked_account_id: Mapped[str | None] = mapped_column(String(100))
    id_proof_url: Mapped[str | None] = mapped_column(Text)
    # Required for bike/scooter, must stay NULL for bicycle.
    vehicle_number: Mapped[str | None] = mapped_column(String(20))
    driving_license_url: Mapped[str | None] = mapped_column(Text)
    bank_account_details: Mapped[dict | None] = mapped_column(JSONB)

    __table_args__ = (
        Index(
            "ix_delivery_partner_profiles_location",
            "current_location",
            postgresql_using="gist",
        ),
    )


# ---------------------------------------------------------------------------
# Addresses
# ---------------------------------------------------------------------------


class Address(TimestampMixin, Base):
    __tablename__ = "addresses"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    customer_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    label: Mapped[str] = mapped_column(String(60), nullable=False)
    location: Mapped[object] = mapped_column(
        Geography("POINT", srid=4326, spatial_index=False), nullable=False
    )
    address_text: Mapped[str] = mapped_column(Text, nullable=False)

    __table_args__ = (
        Index("ix_addresses_location", "location", postgresql_using="gist"),
    )


# ---------------------------------------------------------------------------
# Shops & Subscriptions
# ---------------------------------------------------------------------------


class Shop(TimestampMixin, Base):
    __tablename__ = "shops"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    owner_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), unique=True, nullable=False
    )
    name: Mapped[str] = mapped_column(String(160), nullable=False)
    category: Mapped[str] = mapped_column(String(80), nullable=False)
    location: Mapped[object] = mapped_column(
        Geography("POINT", srid=4326, spatial_index=False), nullable=False
    )
    delivery_radius_km: Mapped[int] = mapped_column(
        SmallInteger, nullable=False, server_default="4"
    )
    is_open: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    subscription_status: Mapped[SubscriptionStatus] = mapped_column(
        String(20), nullable=False, server_default="trial"
    )
    razorpay_linked_account_id: Mapped[str | None] = mapped_column(String(100))

    __table_args__ = (
        Index("ix_shops_location", "location", postgresql_using="gist"),
    )


class SubscriptionPlan(TimestampMixin, Base):
    __tablename__ = "subscription_plans"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    name: Mapped[str] = mapped_column(String(60), unique=True, nullable=False)
    price_paise: Mapped[int] = mapped_column(Integer, nullable=False)

    __table_args__ = (
        CheckConstraint("price_paise >= 0", name="nonneg_plan_price"),
    )


class ShopSubscription(TimestampMixin, Base):
    __tablename__ = "shop_subscriptions"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    shop_id: Mapped[UUID] = mapped_column(
        ForeignKey("shops.id", ondelete="CASCADE"), nullable=False, index=True
    )
    plan_id: Mapped[UUID] = mapped_column(
        ForeignKey("subscription_plans.id", ondelete="RESTRICT"), nullable=False
    )
    is_trial: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    trial_start_date: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    trial_end_date: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    razorpay_subscription_id: Mapped[str | None] = mapped_column(String(100))


# ---------------------------------------------------------------------------
# Products
# ---------------------------------------------------------------------------


class Product(TimestampMixin, Base):
    __tablename__ = "products"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    shop_id: Mapped[UUID] = mapped_column(
        ForeignKey("shops.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(160), nullable=False)
    price_paise: Mapped[int] = mapped_column(Integer, nullable=False)
    unit: Mapped[str] = mapped_column(String(40), nullable=False)
    stock_status: Mapped[StockStatus] = mapped_column(
        String(20), nullable=False, server_default="available"
    )

    __table_args__ = (
        CheckConstraint("price_paise >= 0", name="nonneg_product_price"),
    )


# ---------------------------------------------------------------------------
# Orders
# ---------------------------------------------------------------------------


class Order(TimestampMixin, Base):
    __tablename__ = "orders"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    customer_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    shop_id: Mapped[UUID] = mapped_column(
        ForeignKey("shops.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    # The drop-off. Needed to route a delivery at all, and specifically to
    # measure a Tier 2 detour against the partner's existing drop-off.
    # Nullable because orders placed before this column existed have none.
    delivery_address_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("addresses.id", ondelete="RESTRICT"), index=True
    )
    status: Mapped[OrderStatus] = mapped_column(String(40), nullable=False, index=True)
    item_total_paise: Mapped[int] = mapped_column(Integer, nullable=False)
    delivery_fee_paise: Mapped[int] = mapped_column(Integer, nullable=False)
    payment_mode: Mapped[PaymentMode] = mapped_column(String(10), nullable=False)
    payment_status: Mapped[str] = mapped_column(
        String(20), nullable=False, server_default="pending"
    )
    razorpay_order_id: Mapped[str | None] = mapped_column(String(100))
    delivery_otp: Mapped[str | None] = mapped_column(String(4))
    idempotency_key: Mapped[str | None] = mapped_column(String(36))
    matching_requires_attention: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default="false"
    )
    cancellation_deduction_paise: Mapped[int] = mapped_column(
        Integer, nullable=False, server_default="0"
    )

    __table_args__ = (
        Index(
            "uq_orders_idempotency_key",
            "idempotency_key",
            unique=True,
            postgresql_where=idempotency_key.is_not(None),
        ),
        CheckConstraint("item_total_paise >= 0", name="nonneg_item_total"),
        CheckConstraint("delivery_fee_paise >= 0", name="nonneg_delivery_fee"),
        CheckConstraint(
            "cancellation_deduction_paise >= 0",
            name="nonneg_cancellation_deduction",
        ),
        CheckConstraint(
            "delivery_otp IS NULL OR (length(delivery_otp) = 4 AND delivery_otp ~ '^[0-9]{4}$')",
            name="valid_delivery_otp",
        ),
    )


class OrderItem(TimestampMixin, Base):
    __tablename__ = "order_items"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    order_id: Mapped[UUID] = mapped_column(
        ForeignKey("orders.id", ondelete="CASCADE"), nullable=False, index=True
    )
    product_id: Mapped[UUID] = mapped_column(
        ForeignKey("products.id", ondelete="RESTRICT"), nullable=False
    )
    qty: Mapped[int] = mapped_column(Integer, nullable=False)
    price_at_order_time_paise: Mapped[int] = mapped_column(Integer, nullable=False)
    availability_status: Mapped[ItemAvailability] = mapped_column(
        String(20), nullable=False, server_default="available"
    )
    unavailable_reason: Mapped[str | None] = mapped_column(Text)

    __table_args__ = (
        CheckConstraint("qty > 0", name="positive_qty"),
        CheckConstraint("price_at_order_time_paise >= 0", name="nonneg_item_price"),
    )


class OrderStatusHistory(TimestampMixin, Base):
    __tablename__ = "order_status_history"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    order_id: Mapped[UUID] = mapped_column(
        ForeignKey("orders.id", ondelete="CASCADE"), nullable=False, index=True
    )
    status: Mapped[OrderStatus] = mapped_column(String(40), nullable=False)


class OrderPhoto(TimestampMixin, Base):
    __tablename__ = "order_photos"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    order_id: Mapped[UUID] = mapped_column(
        ForeignKey("orders.id", ondelete="CASCADE"), nullable=False, index=True
    )
    captured_by: Mapped[PhotoCapturedBy] = mapped_column(String(20), nullable=False)
    stage: Mapped[PhotoStage] = mapped_column(String(20), nullable=False)
    photo_url: Mapped[str] = mapped_column(Text, nullable=False)


# ---------------------------------------------------------------------------
# Delivery
# ---------------------------------------------------------------------------


class DeliveryAssignment(TimestampMixin, Base):
    __tablename__ = "delivery_assignments"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    order_id: Mapped[UUID] = mapped_column(
        ForeignKey("orders.id", ondelete="CASCADE"), nullable=False, index=True
    )
    partner_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    trip_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False, index=True)
    pickup_code: Mapped[str] = mapped_column(String(4), nullable=False)
    assigned_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, server_default="offered", index=True
    )
    accepted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    declined_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    expired_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    timeout_task_id: Mapped[str | None] = mapped_column(String(100))
    cascade_count: Mapped[int] = mapped_column(
        SmallInteger, nullable=False, server_default="0"
    )
    offer_type: Mapped[OfferType] = mapped_column(
        String(20), nullable=False, server_default="fresh"
    )
    # Added route distance for a Tier 2 detour offer; NULL for fresh offers.
    detour_meters: Mapped[int | None] = mapped_column(Integer)
    # Accept window in seconds — 35 for fresh, 20 for batch_detour. Stored as
    # data so neither value is hardcoded at the call site.
    window_seconds: Mapped[int | None] = mapped_column(SmallInteger)

    __table_args__ = (
        CheckConstraint(
            "length(pickup_code) = 4 AND pickup_code ~ '^[0-9]{4}$'",
            name="valid_pickup_code",
        ),
        CheckConstraint(
            "detour_meters IS NULL OR detour_meters >= 0",
            name="nonneg_detour_meters",
        ),
    )


class LiveLocation(TimestampMixin, Base):
    __tablename__ = "live_locations"

    partner_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    location: Mapped[object] = mapped_column(
        Geography("POINT", srid=4326, spatial_index=False), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    __table_args__ = (
        Index("ix_live_locations_location", "location", postgresql_using="gist"),
    )


# ---------------------------------------------------------------------------
# Payments & Wallets
# ---------------------------------------------------------------------------


class Payment(TimestampMixin, Base):
    __tablename__ = "payments"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    order_id: Mapped[UUID] = mapped_column(
        ForeignKey("orders.id", ondelete="CASCADE"), nullable=False, index=True
    )
    razorpay_payment_id: Mapped[str | None] = mapped_column(String(100))
    razorpay_order_id: Mapped[str | None] = mapped_column(String(100))
    amount_paise: Mapped[int] = mapped_column(Integer, nullable=False)
    status: Mapped[PaymentStatus] = mapped_column(String(20), nullable=False)

    __table_args__ = (
        Index(
            "uq_payments_razorpay_payment_id",
            "razorpay_payment_id",
            unique=True,
            postgresql_where=razorpay_payment_id.is_not(None),
        ),
        CheckConstraint("amount_paise >= 0", name="nonneg_payment"),
    )


class Refund(TimestampMixin, Base):
    __tablename__ = "refunds"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    order_id: Mapped[UUID] = mapped_column(
        ForeignKey("orders.id", ondelete="CASCADE"), nullable=False, index=True
    )
    razorpay_refund_id: Mapped[str | None] = mapped_column(String(100))
    amount_paise: Mapped[int] = mapped_column(Integer, nullable=False)
    reason: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[RefundStatus] = mapped_column(String(20), nullable=False)

    __table_args__ = (
        Index(
            "uq_refunds_razorpay_refund_id",
            "razorpay_refund_id",
            unique=True,
            postgresql_where=razorpay_refund_id.is_not(None),
        ),
        CheckConstraint("amount_paise >= 0", name="nonneg_refund"),
    )


class Wallet(TimestampMixin, Base):
    __tablename__ = "wallets"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    owner_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    owner_type: Mapped[WalletOwnerType] = mapped_column(String(20), nullable=False)
    balance_paise: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")

    __table_args__ = (
        CheckConstraint("balance_paise >= 0", name="nonneg_balance"),
    )


class WalletTransaction(TimestampMixin, Base):
    __tablename__ = "wallet_transactions"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    wallet_id: Mapped[UUID] = mapped_column(
        ForeignKey("wallets.id", ondelete="CASCADE"), nullable=False, index=True
    )
    type: Mapped[WalletTxnType] = mapped_column(String(20), nullable=False)
    amount_paise: Mapped[int] = mapped_column(Integer, nullable=False)
    order_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("orders.id", ondelete="SET NULL")
    )
    settlement_channel: Mapped[str | None] = mapped_column(String(20))
    settled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


# ---------------------------------------------------------------------------
# Ratings & Disputes
# ---------------------------------------------------------------------------


class Rating(TimestampMixin, Base):
    __tablename__ = "ratings"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    order_id: Mapped[UUID] = mapped_column(
        ForeignKey("orders.id", ondelete="CASCADE"), nullable=False, index=True
    )
    rated_by: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
    )
    rated_entity_type: Mapped[RatedEntityType] = mapped_column(String(20), nullable=False)
    score: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    comment: Mapped[str | None] = mapped_column(Text)

    __table_args__ = (
        CheckConstraint("score >= 1 AND score <= 5", name="valid_score"),
    )


class Dispute(TimestampMixin, Base):
    __tablename__ = "disputes"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    order_id: Mapped[UUID] = mapped_column(
        ForeignKey("orders.id", ondelete="CASCADE"), nullable=False, index=True
    )
    raised_by: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
    )
    status: Mapped[DisputeStatus] = mapped_column(String(20), nullable=False)
    resolution: Mapped[str | None] = mapped_column(Text)
    linked_photo_ids: Mapped[list[UUID] | None] = mapped_column(ARRAY(PGUUID(as_uuid=True)))
