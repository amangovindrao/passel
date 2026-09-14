"""Pydantic request/response schemas."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict


class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    phone: str
    role: str
    roles: list[str] = []
    created_at: datetime


class HealthResponse(BaseModel):
    status: str
    database: str


# ---------------------------------------------------------------------------
# Group Orders & Private Cart Mode
# ---------------------------------------------------------------------------


class GroupOrderSessionCreate(BaseModel):
    society_name: str
    delivery_address_id: UUID | None = None
    private_cart_mode: bool = False
    duration_minutes: int = 30


class PrivacyToggleRequest(BaseModel):
    enable: bool
    confirm_disable: bool = False


class GroupOrderCartItemIn(BaseModel):
    shop_id: UUID
    product_id: UUID
    qty: int


class GroupOrderCartItemOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    shop_id: UUID
    shop_name: str | None = None
    product_id: UUID
    product_name: str | None = None
    qty: int
    price_at_addition_paise: int
    subtotal_paise: int = 0


class GroupOrderMemberOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    name: str
    is_creator: bool
    status: str
    payment_status: str
    items: list[GroupOrderCartItemOut] = []
    subtotal_paise: int | None = None
    paid_amount_paise: int | None = None
    wallet_amount_used_paise: int | None = None


class GroupOrderProgress(BaseModel):
    member_count: int
    shop_count: int
    carts_ready_count: int
    payments_completed_count: int
    status_text: str
    delivery_savings_paise: int
    group_total_paise: int | None = None


class GroupMemberPayRequest(BaseModel):
    wallet_amount_to_use_paise: int = 0
    payment_mode: str = "online"


class CaptainPayRequest(BaseModel):
    wallet_amount_to_use_paise: int = 0
    payment_mode: str = "online"


class GroupOrderPackageOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    session_id: UUID
    order_id: UUID | None = None
    shop_id: UUID
    member_id: UUID
    handover_otp: str | None = None
    pickup_status: str
    delivery_status: str
    handover_status: str
    handover_type: str


class PackageHandoverRequest(BaseModel):
    package_id: UUID
    verification_code: str


class GroupOrderSessionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    creator_id: UUID
    delivery_address_id: UUID | None
    society_name: str
    status: str
    private_cart_mode: bool
    closes_at: datetime | None
    payment_complete: bool = False
    progress: GroupOrderProgress
    members: list[GroupOrderMemberOut]
    my_cart: list[GroupOrderCartItemOut] = []
    my_subtotal_paise: int = 0
    packages: list[GroupOrderPackageOut] = []


# ---------------------------------------------------------------------------
# Delivery Verification & 7-Minute Window
# ---------------------------------------------------------------------------


class DeliveryHandoverStartResponse(BaseModel):
    order_id: UUID
    handover_initiated_at: datetime | None = None
    verification_deadline: datetime | None = None
    remaining_seconds: int = 0
    status: str
    verification_status: str


class CustomerVerifyOrderRequest(BaseModel):
    action: str  # "everything_correct" | "report_issue"


class ReportIssueRequest(BaseModel):
    issue_type: str  # "MISSING_ITEM" | "WRONG_ITEM" | "DAMAGED_ITEM" | "EXPIRED_ITEM" | "OTHER"
    order_item_id: UUID
    customer_notes: str | None = None
    evidence_photo_url: str | None = None


class OrderReturnOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    order_id: UUID
    order_item_id: UUID
    return_reason: str
    status: str
    return_charge_payer: str
    refund_amount_paise: int
    is_expired_item: bool
    created_at: datetime


# ---------------------------------------------------------------------------
# "Add More to This Order"
# ---------------------------------------------------------------------------


class OrderAdditionCheckResponse(BaseModel):
    order_id: UUID
    addition_window_status: str
    is_eligible: bool
    reason: str | None = None
    shop_id: UUID
    shop_name: str


class OrderAdditionItemIn(BaseModel):
    product_id: UUID
    qty: int


class OrderAdditionCreateRequest(BaseModel):
    items: list[OrderAdditionItemIn]
    wallet_amount_to_use_paise: int = 0
    payment_mode: str = "online"
    idempotency_key: str | None = None


class OrderAdditionItemOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    product_id: UUID
    product_name: str | None = None
    qty: int
    price_at_addition_paise: int


class OrderAdditionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    original_order_id: UUID
    status: str
    item_total_paise: int
    delivery_fee_adjustment_paise: int = 0
    total_addition_paise: int
    wallet_amount_used_paise: int = 0
    external_amount_paise: int = 0
    payment_status: str
    items: list[OrderAdditionItemOut] = []
    created_at: datetime

