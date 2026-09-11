"""All domain enums — single source of truth."""

from enum import StrEnum


class UserRole(StrEnum):
    CUSTOMER = "customer"
    SHOP_OWNER = "shop_owner"
    DELIVERY_PARTNER = "delivery_partner"
    ADMIN = "admin"


class KycStatus(StrEnum):
    PENDING = "pending"
    SUBMITTED = "submitted"
    APPROVED = "approved"
    REJECTED = "rejected"


class VehicleType(StrEnum):
    BICYCLE = "bicycle"
    BIKE = "bike"
    SCOOTER = "scooter"

    @property
    def requires_registration(self) -> bool:
        """Motorised vehicles need a plate number and a driving licence."""
        return self is not VehicleType.BICYCLE


class SubscriptionStatus(StrEnum):
    TRIAL = "trial"
    ACTIVE = "active"
    PAST_DUE = "past_due"
    SUSPENDED = "suspended"


class StockStatus(StrEnum):
    AVAILABLE = "available"
    UNAVAILABLE = "unavailable"


class OrderStatus(StrEnum):
    PLACED = "PLACED"
    ACCEPTED_BY_SHOP = "ACCEPTED_BY_SHOP"
    REJECTED_BY_SHOP = "REJECTED_BY_SHOP"
    PREPARING = "PREPARING"
    AWAITING_CUSTOMER_DECISION = "AWAITING_CUSTOMER_DECISION"
    ON_HOLD = "ON_HOLD"
    CANCELLED_ITEM_UNAVAILABLE = "CANCELLED_ITEM_UNAVAILABLE"
    READY_FOR_PICKUP = "READY_FOR_PICKUP"
    PARTNER_ASSIGNED = "PARTNER_ASSIGNED"
    PARTNER_ARRIVED_AT_SHOP = "PARTNER_ARRIVED_AT_SHOP"
    PICKED_UP = "PICKED_UP"
    OUT_FOR_DELIVERY = "OUT_FOR_DELIVERY"
    DELIVERED = "DELIVERED"
    COMPLETED = "COMPLETED"
    CANCELLED_BY_CUSTOMER = "CANCELLED_BY_CUSTOMER"
    CANCELLED_BY_SHOP = "CANCELLED_BY_SHOP"


class AssignmentStatus(StrEnum):
    OFFERED = "offered"
    ACCEPTED = "accepted"
    DECLINED = "declined"
    EXPIRED = "expired"


class OfferType(StrEnum):
    FRESH = "fresh"
    BATCH_DETOUR = "batch_detour"


class PaymentMode(StrEnum):
    ONLINE = "online"
    COD = "cod"


class ItemAvailability(StrEnum):
    AVAILABLE = "available"
    UNAVAILABLE = "unavailable"


class PhotoCapturedBy(StrEnum):
    SHOP = "shop"
    DELIVERY_PARTNER = "delivery_partner"


class PhotoStage(StrEnum):
    PACKING = "packing"
    PICKUP = "pickup"
    DELIVERY = "delivery"


class PaymentStatus(StrEnum):
    PENDING = "pending"
    CAPTURED = "captured"
    FAILED = "failed"


class RefundStatus(StrEnum):
    PENDING = "pending"
    PROCESSED = "processed"
    FAILED = "failed"


class WalletOwnerType(StrEnum):
    DELIVERY_PARTNER = "delivery_partner"
    SHOP = "shop"


class WalletTxnType(StrEnum):
    EARNING = "earning"
    COD_DEBIT = "cod_debit"
    PAYOUT = "payout"


class RatedEntityType(StrEnum):
    SHOP = "shop"
    DELIVERY_PARTNER = "delivery_partner"


class DisputeStatus(StrEnum):
    OPEN = "open"
    INVESTIGATING = "investigating"
    RESOLVED = "resolved"
    CLOSED = "closed"
