"""The shop's side of an order: seeing the queue, and being allowed to act on it.

Two things are pinned down here. First the list and detail endpoints, which did
not exist — a customer could place an order and no shop owner had any way to
learn it had happened. Second, and more importantly, that the action endpoints
actually check whose shop the order belongs to. That check was an empty function
body for the whole life of the router, and no test called those endpoints over
HTTP, so nothing noticed: any signed-in shop owner could accept, reject, or hand
off an order belonging to any other shop.
"""

from sqlalchemy import select

from app.domain.enums import ItemAvailability, KycStatus, OrderStatus
from app.models.entities import Order
from tests.factories import (
    make_assignment,
    make_order,
    make_order_item,
    make_partner,
    make_product,
    make_shop,
    make_user,
)


def orders_url(shop_id) -> str:
    return f"/api/v1/shops/{shop_id}/orders"


async def _cod_order(db, shop, *, status=OrderStatus.PLACED, **kwargs):
    """A COD order. COD on purpose: an unpaid online order is refused by the
    payment guard, which would mask whatever the test is actually asking."""
    return await make_order(
        db, shop=shop, status=status, payment_mode="cod", **kwargs
    )


# ---------------------------------------------------------------------------
# Authorization on the action endpoints
# ---------------------------------------------------------------------------


async def test_another_owner_cannot_accept_your_order(api, db_session):
    """The role gate only proves *a* shop owner is calling, not which one."""
    mine = await make_shop(db_session)
    intruder = await make_user(db_session, "shop_owner")
    order = await _cod_order(db_session, mine)
    # Held separately: expire_all() below expires the identity too, and reading
    # it back off the instance would itself trigger a lazy load.
    order_id = order.id

    resp = await api.as_user(intruder).post(f"/api/v1/orders/{order_id}/accept")

    assert resp.status_code == 403
    assert resp.json()["error"]["code"] == "forbidden"

    # And the order is untouched, not merely un-reported.
    db_session.expire_all()
    status = await db_session.scalar(
        select(Order.status).where(Order.id == order_id)
    )
    assert status == OrderStatus.PLACED.value


async def test_another_owner_cannot_reject_your_order(api, db_session):
    mine = await make_shop(db_session)
    intruder = await make_user(db_session, "shop_owner")
    order = await _cod_order(db_session, mine)

    resp = await api.as_user(intruder).post(
        f"/api/v1/orders/{order.id}/reject"
    )

    assert resp.status_code == 403


async def test_another_owner_cannot_mark_your_order_ready(api, db_session):
    mine = await make_shop(db_session)
    intruder = await make_user(db_session, "shop_owner")
    order = await _cod_order(db_session, mine, status=OrderStatus.PREPARING)

    resp = await api.as_user(intruder).post(
        f"/api/v1/orders/{order.id}/mark-ready"
    )

    assert resp.status_code == 403


async def test_another_owner_cannot_attach_a_packing_photo(api, db_session):
    """Otherwise the ready-for-pickup guard is satisfiable by a stranger."""
    mine = await make_shop(db_session)
    intruder = await make_user(db_session, "shop_owner")
    order = await _cod_order(db_session, mine, status=OrderStatus.PREPARING)

    resp = await api.as_user(intruder).post(
        f"/api/v1/orders/{order.id}/packing-photo",
        json={"photo_url": "https://example.test/x.jpg"},
    )

    assert resp.status_code == 403


async def test_another_owner_cannot_mark_an_item_unavailable(api, db_session):
    mine = await make_shop(db_session)
    intruder = await make_user(db_session, "shop_owner")
    order = await _cod_order(db_session, mine, status=OrderStatus.PREPARING)
    item = await make_order_item(db_session, order, shop=mine)

    resp = await api.as_user(intruder).post(
        f"/api/v1/orders/{order.id}/items/{item.id}/mark-unavailable",
        json={"reason": "out of stock"},
    )

    assert resp.status_code == 403


async def test_the_real_owner_can_accept(api, db_session):
    """The other half of the check: it must not lock the rightful owner out."""
    owner = await make_user(db_session, "shop_owner")
    shop = await make_shop(db_session, owner=owner)
    order = await _cod_order(db_session, shop)

    resp = await api.as_user(owner).post(f"/api/v1/orders/{order.id}/accept")

    assert resp.status_code == 200
    # accept walks ACCEPTED_BY_SHOP then PREPARING in one call.
    assert resp.json()["status"] == OrderStatus.PREPARING.value


# ---------------------------------------------------------------------------
# GET the order queue
# ---------------------------------------------------------------------------


async def test_queue_lists_only_your_own_shops_orders(api, db_session):
    owner = await make_user(db_session, "shop_owner")
    shop = await make_shop(db_session, owner=owner)
    other = await make_shop(db_session)

    await _cod_order(db_session, shop)
    await _cod_order(db_session, other)

    resp = await api.as_user(owner).get(orders_url(shop.id))

    assert resp.status_code == 200
    assert len(resp.json()) == 1


async def test_queue_refuses_someone_elses_shop(api, db_session):
    intruder = await make_user(db_session, "shop_owner")
    shop = await make_shop(db_session)
    await _cod_order(db_session, shop)

    resp = await api.as_user(intruder).get(orders_url(shop.id))

    assert resp.status_code == 403


async def test_queue_defaults_to_orders_still_needing_attention(
    api, db_session
):
    """A worklist, not a ledger. Finished orders would only ever be noise."""
    owner = await make_user(db_session, "shop_owner")
    shop = await make_shop(db_session, owner=owner)

    await _cod_order(db_session, shop)
    await _cod_order(db_session, shop, status=OrderStatus.PREPARING)
    await _cod_order(db_session, shop, status=OrderStatus.DELIVERED)
    await _cod_order(db_session, shop, status=OrderStatus.COMPLETED)
    await _cod_order(db_session, shop, status=OrderStatus.REJECTED_BY_SHOP)

    body = (await api.as_user(owner).get(orders_url(shop.id))).json()

    statuses = {o["status"] for o in body}
    assert statuses == {
        OrderStatus.PLACED.value,
        OrderStatus.PREPARING.value,
    }


async def test_queue_accepts_an_explicit_status_filter(api, db_session):
    owner = await make_user(db_session, "shop_owner")
    shop = await make_shop(db_session, owner=owner)
    await _cod_order(db_session, shop)
    await _cod_order(db_session, shop, status=OrderStatus.DELIVERED)

    body = (
        await api.as_user(owner).get(
            orders_url(shop.id), params={"status": "DELIVERED"}
        )
    ).json()

    assert [o["status"] for o in body] == [OrderStatus.DELIVERED.value]


async def test_queue_rejects_a_status_that_does_not_exist(api, db_session):
    """Silently returning nothing would read as "no orders" and waste an hour."""
    owner = await make_user(db_session, "shop_owner")
    shop = await make_shop(db_session, owner=owner)

    resp = await api.as_user(owner).get(
        orders_url(shop.id), params={"status": "COOKING"}
    )

    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "invalid_status"


async def test_queue_counts_items_by_quantity(api, db_session):
    """Five things to pack, not two lines on a receipt."""
    owner = await make_user(db_session, "shop_owner")
    shop = await make_shop(db_session, owner=owner)
    order = await _cod_order(db_session, shop)
    await make_order_item(db_session, order, shop=shop, qty=2)
    await make_order_item(db_session, order, shop=shop, qty=3)

    body = (await api.as_user(owner).get(orders_url(shop.id))).json()

    assert body[0]["item_count"] == 5


async def test_queue_includes_an_order_with_no_items_at_all(api, db_session):
    """An outer join, so a malformed order is visible rather than invisible."""
    owner = await make_user(db_session, "shop_owner")
    shop = await make_shop(db_session, owner=owner)
    await _cod_order(db_session, shop)

    body = (await api.as_user(owner).get(orders_url(shop.id))).json()

    assert len(body) == 1
    assert body[0]["item_count"] == 0


async def test_queue_flags_an_online_order_nobody_has_paid_for(
    api, db_session
):
    """The shop cannot accept it, so the list has to say why."""
    owner = await make_user(db_session, "shop_owner")
    shop = await make_shop(db_session, owner=owner)
    await make_order(
        db_session, shop=shop, payment_mode="online", payment_status="pending"
    )

    body = (await api.as_user(owner).get(orders_url(shop.id))).json()

    assert body[0]["awaiting_payment"] is True


async def test_queue_does_not_flag_a_cod_order_as_awaiting_payment(
    api, db_session
):
    owner = await make_user(db_session, "shop_owner")
    shop = await make_shop(db_session, owner=owner)
    await _cod_order(db_session, shop)

    body = (await api.as_user(owner).get(orders_url(shop.id))).json()

    assert body[0]["awaiting_payment"] is False


# ---------------------------------------------------------------------------
# GET one order
# ---------------------------------------------------------------------------


async def test_detail_carries_the_lines_with_product_names(api, db_session):
    owner = await make_user(db_session, "shop_owner")
    shop = await make_shop(db_session, owner=owner)
    order = await _cod_order(db_session, shop)
    product = await make_product(
        db_session, shop, name="Toned Milk 500ml", price_paise=2700
    )
    await make_order_item(
        db_session, order, product=product, qty=2, price_paise=2700
    )

    body = (
        await api.as_user(owner).get(f"{orders_url(shop.id)}/{order.id}")
    ).json()

    assert len(body["items"]) == 1
    line = body["items"][0]
    assert line["name"] == "Toned Milk 500ml"
    assert line["qty"] == 2
    assert line["line_total_paise"] == 5400
    assert line["availability_status"] == ItemAvailability.AVAILABLE.value


async def test_detail_excludes_unavailable_lines_from_the_available_total(
    api, db_session
):
    """What the shop can actually supply, which is what the refund keys off."""
    owner = await make_user(db_session, "shop_owner")
    shop = await make_shop(db_session, owner=owner)
    order = await _cod_order(db_session, shop, status=OrderStatus.PREPARING)
    await make_order_item(db_session, order, shop=shop, qty=1, price_paise=1000)
    gone = await make_order_item(
        db_session, order, shop=shop, qty=1, price_paise=4000
    )
    gone.availability_status = ItemAvailability.UNAVAILABLE.value
    await db_session.flush()

    body = (
        await api.as_user(owner).get(f"{orders_url(shop.id)}/{order.id}")
    ).json()

    assert body["available_item_total_paise"] == 1000
    # Both lines are still listed — the shop needs to see what it dropped.
    assert len(body["items"]) == 2


async def test_detail_refuses_another_shops_order(api, db_session):
    owner = await make_user(db_session, "shop_owner")
    mine = await make_shop(db_session, owner=owner)
    theirs = await make_shop(db_session)
    order = await _cod_order(db_session, theirs)

    resp = await api.as_user(owner).get(f"{orders_url(mine.id)}/{order.id}")

    assert resp.status_code == 404


async def test_detail_says_a_placed_cod_order_can_be_accepted(api, db_session):
    owner = await make_user(db_session, "shop_owner")
    shop = await make_shop(db_session, owner=owner)
    order = await _cod_order(db_session, shop)

    body = (
        await api.as_user(owner).get(f"{orders_url(shop.id)}/{order.id}")
    ).json()

    assert body["can_accept"] is True


async def test_detail_says_an_unpaid_online_order_cannot_be_accepted(
    api, db_session
):
    owner = await make_user(db_session, "shop_owner")
    shop = await make_shop(db_session, owner=owner)
    order = await make_order(
        db_session, shop=shop, payment_mode="online", payment_status="pending"
    )

    body = (
        await api.as_user(owner).get(f"{orders_url(shop.id)}/{order.id}")
    ).json()

    assert body["can_accept"] is False
    assert body["awaiting_payment"] is True


# --- can_mark_ready mirrors the state machine's packing-photo guard ---


async def test_mark_ready_is_refused_until_a_packing_photo_exists(
    api, db_session
):
    """A live-looking button that always 422s is worse than a disabled one."""
    owner = await make_user(db_session, "shop_owner")
    shop = await make_shop(db_session, owner=owner)
    order = await _cod_order(db_session, shop, status=OrderStatus.PREPARING)

    before = (
        await api.as_user(owner).get(f"{orders_url(shop.id)}/{order.id}")
    ).json()
    assert before["has_packing_photo"] is False
    assert before["can_mark_ready"] is False

    # The server agrees with what it just advertised.
    blocked = await api.as_user(owner).post(
        f"/api/v1/orders/{order.id}/mark-ready"
    )
    assert blocked.status_code == 422
    assert "packing photo" in blocked.json()["error"]["message"].lower()


async def test_mark_ready_is_allowed_once_the_photo_is_attached(
    api, db_session
):
    owner = await make_user(db_session, "shop_owner")
    shop = await make_shop(db_session, owner=owner)
    order = await _cod_order(db_session, shop, status=OrderStatus.PREPARING)

    uploaded = await api.as_user(owner).post(
        f"/api/v1/orders/{order.id}/packing-photo",
        json={"photo_url": "https://example.test/packed.jpg"},
    )
    assert uploaded.status_code == 200

    body = (
        await api.as_user(owner).get(f"{orders_url(shop.id)}/{order.id}")
    ).json()

    assert body["has_packing_photo"] is True
    assert body["can_mark_ready"] is True


# --- The pickup code is the rider's, and only once there is a rider ---


async def test_pickup_code_is_withheld_before_a_rider_is_assigned(
    api, db_session
):
    owner = await make_user(db_session, "shop_owner")
    shop = await make_shop(db_session, owner=owner)
    order = await _cod_order(
        db_session, shop, status=OrderStatus.READY_FOR_PICKUP
    )

    body = (
        await api.as_user(owner).get(f"{orders_url(shop.id)}/{order.id}")
    ).json()

    assert body["pickup_code"] is None


async def test_pickup_code_appears_once_a_rider_is_on_the_way(api, db_session):
    """This is what the shop checks against the rider standing at the counter."""
    owner = await make_user(db_session, "shop_owner")
    shop = await make_shop(db_session, owner=owner)
    order = await _cod_order(
        db_session, shop, status=OrderStatus.PARTNER_ASSIGNED
    )
    partner = await make_partner(
        db_session, lng=77.5990, kyc_status=KycStatus.APPROVED.value
    )
    await make_assignment(
        db_session, order, partner, pickup_code="8241", accepted=True
    )

    body = (
        await api.as_user(owner).get(f"{orders_url(shop.id)}/{order.id}")
    ).json()

    assert body["pickup_code"] == "8241"
