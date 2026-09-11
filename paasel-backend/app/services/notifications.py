"""Push notification seam.

Two channels carry state to the apps, and they do different jobs:

* Supabase Realtime — the apps subscribe to row changes directly, so writing a
  row *is* the update for anything a foregrounded screen watches (queue lists,
  order status, KYC approval). Nothing needs to be published here for that.
* Push (FCM) — required when the app is backgrounded or closed and a human has
  to be interrupted: a rider's phone in a pocket, a shop tablet with the screen
  off. Realtime cannot wake a dead app; only a push can.

This module is the single place the second channel gets wired. Until a sender
is configured every call is a structured log, which keeps the call sites honest
about when a push is owed instead of scattering TODOs through the services.
"""

from typing import Any
from uuid import UUID

import structlog

log = structlog.get_logger()


async def push_to_partner(
    partner_id: UUID,
    *,
    kind: str,
    payload: dict[str, Any],
) -> None:
    """High-priority data message to one delivery partner.

    `kind` is what the rider app switches on to decide which surface to show
    (`offer_fresh`, `offer_batch_detour`, `batch_added`).
    """
    log.info(
        "push_to_partner",
        partner_id=str(partner_id),
        kind=kind,
        payload=payload,
    )


async def push_to_shop(
    shop_id: UUID,
    *,
    kind: str,
    payload: dict[str, Any],
) -> None:
    """Data message to a shop owner's device."""
    log.info("push_to_shop", shop_id=str(shop_id), kind=kind, payload=payload)


async def push_to_customer(
    customer_id: UUID,
    *,
    kind: str,
    payload: dict[str, Any],
) -> None:
    """Data message to a customer's device."""
    log.info(
        "push_to_customer",
        customer_id=str(customer_id),
        kind=kind,
        payload=payload,
    )
