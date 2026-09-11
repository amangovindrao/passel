"""Async row factories for DB-backed tests.

Every model here carries raw ForeignKey columns with no `relationship()`, so
SQLAlchemy's unit of work has no way to work out that a `users` row must be
inserted before the rows referencing it. Each factory therefore flushes its own
parents before adding anything that points at them.

These exist because the test suite was originally written against ids conjured
with `uuid4()` and no matching rows — which passes only as long as nothing ever
reaches a real database with real foreign keys.
"""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

from app.domain.enums import (
    ItemAvailability,
    KycStatus,
    OrderStatus,
    PaymentMode,
)
from app.models.entities import (
    Address,
    DeliveryAssignment,
    DeliveryPartnerProfile,
    LiveLocation,
    Order,
    OrderItem,
    Product,
    Shop,
    ShopOwnerProfile,
    User,
)

# Bengaluru city centre, the anchor every geo test measures from.
CENTRE_LNG = 77.5946
CENTRE_LAT = 12.9716


def point(lng: float, lat: float = CENTRE_LAT) -> str:
    return f'SRID=4326;POINT({lng} {lat})'


async def make_user(db, role: str = 'customer') -> User:
    user = User(
        id=uuid4(), phone=f'+91{uuid4().int % 10**10:010d}', role=role
    )
    db.add(user)
    await db.flush()
    return user


async def make_shop(
    db,
    *,
    owner: User | None = None,
    lng: float = CENTRE_LNG,
    lat: float = CENTRE_LAT,
    is_open: bool = True,
    subscription_status: str = 'active',
    kyc_status: str = KycStatus.APPROVED.value,
) -> Shop:
    owner = owner or await make_user(db, 'shop_owner')
    db.add(
        ShopOwnerProfile(
            user_id=owner.id, name='Test Owner', kyc_status=kyc_status
        )
    )
    shop = Shop(
        id=uuid4(),
        owner_id=owner.id,
        name='Test Shop',
        category='grocery',
        location=point(lng, lat),
        delivery_radius_km=4,
        is_open=is_open,
        subscription_status=subscription_status,
    )
    db.add(shop)
    await db.flush()
    return shop


async def make_product(
    db, shop: Shop, *, price_paise: int = 6000, name: str = 'Test Product'
) -> Product:
    product = Product(
        id=uuid4(),
        shop_id=shop.id,
        name=name,
        price_paise=price_paise,
        unit='pc',
        stock_status='available',
    )
    db.add(product)
    await db.flush()
    return product


async def make_address(
    db,
    customer: User,
    *,
    lng: float = 77.6050,
    lat: float = CENTRE_LAT,
    label: str = 'Home',
) -> Address:
    address = Address(
        id=uuid4(),
        customer_id=customer.id,
        label=label,
        location=point(lng, lat),
        address_text=label,
    )
    db.add(address)
    await db.flush()
    return address


async def make_order(
    db,
    *,
    status: OrderStatus = OrderStatus.PLACED,
    shop: Shop | None = None,
    customer: User | None = None,
    with_address: bool = False,
    dropoff_lng: float = 77.6050,
    item_total_paise: int = 50000,
    delivery_fee_paise: int = 3000,
    payment_mode: str = PaymentMode.ONLINE.value,
    delivery_otp: str | None = '1234',
    **kwargs,
) -> Order:
    shop = shop or await make_shop(db)
    customer = customer or await make_user(db, 'customer')

    address_id = None
    if with_address:
        address = await make_address(db, customer, lng=dropoff_lng)
        address_id = address.id

    order = Order(
        id=uuid4(),
        customer_id=customer.id,
        shop_id=shop.id,
        delivery_address_id=address_id,
        status=status.value,
        item_total_paise=item_total_paise,
        delivery_fee_paise=delivery_fee_paise,
        payment_mode=payment_mode,
        delivery_otp=delivery_otp,
        **kwargs,
    )
    db.add(order)
    await db.flush()
    return order


async def make_order_item(
    db,
    order: Order,
    *,
    product: Product | None = None,
    shop: Shop | None = None,
    qty: int = 1,
    price_paise: int = 6000,
) -> OrderItem:
    if product is None:
        if shop is None:
            shop = await db.get(Shop, order.shop_id)
        product = await make_product(db, shop, price_paise=price_paise)

    item = OrderItem(
        id=uuid4(),
        order_id=order.id,
        product_id=product.id,
        qty=qty,
        price_at_order_time_paise=price_paise,
        availability_status=ItemAvailability.AVAILABLE.value,
    )
    db.add(item)
    await db.flush()
    return item


async def make_partner(
    db,
    *,
    lng: float | None = None,
    lat: float = CENTRE_LAT,
    is_online: bool = True,
    ping_age_seconds: int = 5,
    vehicle_type: str = 'bike',
    kyc_status: str = KycStatus.APPROVED.value,
) -> User:
    """A delivery partner, optionally with a live location."""
    partner = await make_user(db, 'delivery_partner')
    db.add(
        DeliveryPartnerProfile(
            user_id=partner.id,
            name='Test Rider',
            vehicle_type=vehicle_type,
            is_online=is_online,
            kyc_status=kyc_status,
        )
    )
    if lng is not None:
        db.add(
            LiveLocation(
                partner_id=partner.id,
                location=point(lng, lat),
                updated_at=datetime.now(UTC)
                - timedelta(seconds=ping_age_seconds),
            )
        )
    await db.flush()
    return partner


async def make_assignment(
    db,
    order: Order,
    partner: User,
    *,
    trip_id=None,
    pickup_code: str = '5678',
    status: str = 'offered',
    accepted: bool = False,
    **kwargs,
) -> DeliveryAssignment:
    """Extra columns go through kwargs: offer_type, window_seconds,
    detour_meters, assigned_at, cascade_count."""
    assignment = DeliveryAssignment(
        order_id=order.id,
        partner_id=partner.id,
        trip_id=trip_id or uuid4(),
        pickup_code=pickup_code,
        status='accepted' if accepted else status,
        accepted_at=datetime.now(UTC) if accepted else None,
        **kwargs,
    )
    db.add(assignment)
    await db.flush()
    return assignment
