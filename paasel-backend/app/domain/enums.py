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


class OrderType(StrEnum):
    NORMAL_ORDER = "NORMAL_ORDER"
    MULTI_SHOP_ORDER = "MULTI_SHOP_ORDER"
    GROUP_ORDER = "GROUP_ORDER"


class DeliveryStatus(StrEnum):
    NOT_READY = "NOT_READY"
    READY = "READY"
    PICKED_UP = "PICKED_UP"
    OUT_FOR_DELIVERY = "OUT_FOR_DELIVERY"
    HANDOVER_READY = "HANDOVER_READY"
    DELIVERED = "DELIVERED"
    FAILED = "FAILED"


class HandoverType(StrEnum):
    CAPTAIN_HANDOVER = "CAPTAIN_HANDOVER"
    INDIVIDUAL_HANDOVER = "INDIVIDUAL_HANDOVER"
    DIRECT_TO_MEMBER = "DIRECT_TO_MEMBER"


class InventoryReservationStatus(StrEnum):
    RESERVED = "RESERVED"
    COMMITTED = "COMMITTED"
    RELEASED = "RELEASED"
    EXPIRED = "EXPIRED"


class OrderStatus(StrEnum):
    CREATED = "CREATED"
    CART_LOCKED = "CART_LOCKED"
    PAYMENT_PENDING = "PAYMENT_PENDING"
    PAID = "PAID"
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
    HANDOVER_READY = "HANDOVER_READY"
    DELIVERED = "DELIVERED"
    COMPLETED = "COMPLETED"
    CANCELLED_BY_CUSTOMER = "CANCELLED_BY_CUSTOMER"
    CANCELLED_BY_SHOP = "CANCELLED_BY_SHOP"
    REJECTED = "REJECTED"
    REFUNDED = "REFUNDED"
    FAILED = "FAILED"


class GroupOrderStatus(StrEnum):
    OPEN = "OPEN"
    SHOPPING = "SHOPPING"
    PAYMENT_PENDING = "PAYMENT_PENDING"
    LOCKED = "LOCKED"
    PROCESSING = "PROCESSING"
    DELIVERED = "DELIVERED"
    CANCELLED = "CANCELLED"


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
    WALLET = "wallet"


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
    UNPAID = "UNPAID"
    PENDING = "pending"
    PAYMENT_PENDING = "PAYMENT_PENDING"
    PAID = "paid"
    CAPTURED = "captured"
    FAILED = "failed"
    REFUND_PENDING = "REFUND_PENDING"
    REFUNDED = "refunded"
    PARTIALLY_REFUNDED = "PARTIALLY_REFUNDED"


class RefundStatus(StrEnum):
    PENDING = "pending"
    PROCESSED = "processed"
    FAILED = "failed"


class WalletOwnerType(StrEnum):
    USER = "user"
    CUSTOMER = "customer"
    DELIVERY_PARTNER = "delivery_partner"
    SHOP = "shop"


class WalletTxnType(StrEnum):
    EARNING = "earning"
    RIDER_EARNING = "rider_earning"
    COD_DEBIT = "cod_debit"
    PAYOUT = "payout"
    ORDER_WALLET_PAYMENT = "order_wallet_payment"
    ORDER_REFUND = "order_refund"
    ADMIN_ADJUSTMENT = "admin_adjustment"
    TRANSACTION_REVERSAL = "transaction_reversal"


class RatedEntityType(StrEnum):
    SHOP = "shop"
    DELIVERY_PARTNER = "delivery_partner"


class DisputeStatus(StrEnum):
    OPEN = "open"
    INVESTIGATING = "investigating"
    RESOLVED = "resolved"
    CLOSED = "closed"


class ReturnReason(StrEnum):
    EXPIRED_ITEM = "EXPIRED_ITEM"
    WRONG_ITEM = "WRONG_ITEM"
    DAMAGED_ITEM = "DAMAGED_ITEM"
    MISSING_ITEM = "MISSING_ITEM"
    OTHER = "OTHER"


class ReturnStatus(StrEnum):
    RETURN_REQUESTED = "RETURN_REQUESTED"
    RETURN_APPROVED = "RETURN_APPROVED"
    RETURN_ASSIGNED = "RETURN_ASSIGNED"
    RETURN_PICKUP_PENDING = "RETURN_PICKUP_PENDING"
    RETURN_IN_TRANSIT = "RETURN_IN_TRANSIT"
    RETURN_RECEIVED_BY_SHOP = "RETURN_RECEIVED_BY_SHOP"
    RETURN_VERIFIED = "RETURN_VERIFIED"
    REFUND_PENDING = "REFUND_PENDING"
    REFUNDED = "REFUNDED"
    CLOSED = "CLOSED"


class ReturnChargePayer(StrEnum):
    SHOP = "SHOP"
    CUSTOMER = "CUSTOMER"
    PAASSEL = "PAASSEL"
    WAIVED = "WAIVED"


class AdditionWindowStatus(StrEnum):
    ADDITION_OPEN = "ADDITION_OPEN"
    ADDITION_CLOSED = "ADDITION_CLOSED"


class AdditionStatus(StrEnum):
    REQUESTED = "REQUESTED"
    PAYMENT_PENDING = "PAYMENT_PENDING"
    CONFIRMED = "CONFIRMED"
    ACCEPTED_BY_SHOP = "ACCEPTED_BY_SHOP"
    REJECTED_BY_SHOP = "REJECTED_BY_SHOP"
    CANCELLED = "CANCELLED"
    FAILED = "FAILED"
    REFUNDED = "REFUNDED"


class VerificationStatus(StrEnum):
    NOT_INITIATED = "NOT_INITIATED"
    PENDING_CHECK = "PENDING_CHECK"
    ALL_CORRECT = "ALL_CORRECT"
    ISSUE_REPORTED = "ISSUE_REPORTED"
    AUTO_COMPLETED_EXPIRED = "AUTO_COMPLETED_EXPIRED"
