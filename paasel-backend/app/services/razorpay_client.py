"""Razorpay API client — Orders, Refunds, Transfers, Subscriptions, Payouts."""

import hashlib
import hmac
import json
from typing import Any

import httpx

from app.core.config import settings


class RazorpayClient:
    """Thin wrapper over Razorpay's REST API."""

    BASE_URL = "https://api.razorpay.com/v1"

    def __init__(self) -> None:
        self._auth = (settings.razorpay_key_id, settings.razorpay_key_secret)

    # --- Signature Verification ---

    def verify_webhook_signature(
        self, body: bytes, signature: str, secret: str | None = None
    ) -> bool:
        """HMAC-SHA256 verification of Razorpay webhook payload."""
        webhook_secret = (secret or settings.razorpay_key_secret).encode()
        expected = hmac.new(webhook_secret, body, hashlib.sha256).hexdigest()
        return hmac.compare_digest(expected, signature)

    @staticmethod
    def verify_signature_static(body: bytes, signature: str, secret: str) -> bool:
        expected = hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
        return hmac.compare_digest(expected, signature)

    # --- Orders ---

    async def create_order(
        self, amount_paise: int, receipt: str, notes: dict | None = None
    ) -> dict[str, Any]:
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                f"{self.BASE_URL}/orders",
                auth=self._auth,
                json={
                    "amount": amount_paise,
                    "currency": "INR",
                    "receipt": receipt,
                    "notes": notes or {},
                },
            )
            resp.raise_for_status()
            return resp.json()

    # --- Refunds ---

    async def create_partial_refund(
        self, payment_id: str, amount_paise: int, notes: dict | None = None
    ) -> dict[str, Any]:
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                f"{self.BASE_URL}/payments/{payment_id}/refund",
                auth=self._auth,
                json={"amount": amount_paise, "notes": notes or {}},
            )
            resp.raise_for_status()
            return resp.json()

    # --- Route Transfers ---

    async def create_transfer(
        self,
        payment_id: str,
        linked_account_id: str,
        amount_paise: int,
        notes: dict | None = None,
    ) -> dict[str, Any]:
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                f"{self.BASE_URL}/payments/{payment_id}/transfers",
                auth=self._auth,
                json={
                    "transfers": [
                        {
                            "account": linked_account_id,
                            "amount": amount_paise,
                            "currency": "INR",
                            "notes": notes or {},
                        }
                    ]
                },
            )
            resp.raise_for_status()
            return resp.json()

    # --- Linked Accounts ---

    async def create_linked_account(self, details: dict) -> dict[str, Any]:
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                f"{self.BASE_URL}/accounts",
                auth=self._auth,
                json=details,
            )
            resp.raise_for_status()
            return resp.json()

    # --- Subscriptions ---

    async def create_subscription(
        self, plan_id: str, total_count: int = 120, notes: dict | None = None
    ) -> dict[str, Any]:
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                f"{self.BASE_URL}/subscriptions",
                auth=self._auth,
                json={
                    "plan_id": plan_id,
                    "total_count": total_count,
                    "notes": notes or {},
                },
            )
            resp.raise_for_status()
            return resp.json()

    # --- RazorpayX Payouts ---

    async def create_payout(
        self,
        account_number: str,
        amount_paise: int,
        fund_account_id: str,
        purpose: str = "payout",
    ) -> dict[str, Any]:
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                f"{self.BASE_URL}/payouts",
                auth=self._auth,
                json={
                    "account_number": account_number,
                    "fund_account_id": fund_account_id,
                    "amount": amount_paise,
                    "currency": "INR",
                    "mode": "IMPS",
                    "purpose": purpose,
                },
            )
            resp.raise_for_status()
            return resp.json()


# Module-level singleton
razorpay = RazorpayClient()
