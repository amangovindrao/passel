"""Prove the whole login chain works, exactly as the phone will do it.

Signs in through the local Supabase stack with a test OTP, registers with the
Paasel backend using that token, then calls real endpoints. If this passes, the
apps will work; if it fails, it fails in the same place they would.

    python scripts/e2e_login.py
    python scripts/e2e_login.py --supabase http://10.112.197.71:54321
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys

import httpx

DEFAULT_SUPABASE = "http://127.0.0.1:54321"
DEFAULT_API = "http://127.0.0.1:8000"
OTP = "123456"

ACCOUNTS = [
    ("9900000001", "customer", "Demo Customer"),
    ("9900000002", "shop_owner", "Demo Store Owner"),
    ("9900000003", "delivery_partner", "Demo Rider"),
]

ROLE_CHECKS = {
    "customer": [
        ("/api/v1/customers/profile", None),
        ("/api/v1/addresses", None),
        ("/api/v1/shops/nearby", {"lat": 12.9716, "lng": 77.5946}),
    ],
    "shop_owner": [("/api/v1/shops/mine", None)],
    "delivery_partner": [("/api/v1/delivery-partners/me", None)],
}


async def sign_in(client: httpx.AsyncClient, anon_key: str, phone: str) -> str:
    """Phone OTP against the local stack — the same two calls the app makes."""
    headers = {"apikey": anon_key, "Content-Type": "application/json"}

    sent = await client.post(
        "/auth/v1/otp", headers=headers, json={"phone": f"+91{phone}"}
    )
    if sent.status_code >= 400:
        raise RuntimeError(f"otp request failed: {sent.status_code} {sent.text}")

    verified = await client.post(
        "/auth/v1/verify",
        headers=headers,
        json={"type": "sms", "phone": f"+91{phone}", "token": OTP},
    )
    if verified.status_code >= 400:
        raise RuntimeError(
            f"otp verify failed: {verified.status_code} {verified.text}"
        )
    token = verified.json().get("access_token")
    if not token:
        raise RuntimeError(f"no access_token in verify response: {verified.text}")
    return token


async def run(supabase_url: str, api_url: str, anon_key: str) -> int:
    failures = 0

    async with (
        httpx.AsyncClient(base_url=supabase_url, timeout=20) as supabase,
        httpx.AsyncClient(base_url=api_url, timeout=20) as api,
    ):
        health = await api.get("/health")
        print(f"api /health                     -> {health.status_code} {health.text}")
        if health.status_code != 200:
            print("\nThe API is not healthy. Nothing else will work.")
            return 1

        for phone, role, name in ACCOUNTS:
            print(f"\n--- {role}  (+91{phone}) ---")
            try:
                token = await sign_in(supabase, anon_key, phone)
            except RuntimeError as exc:
                print(f"  supabase login                -> FAILED: {exc}")
                failures += 1
                continue
            print(f"  supabase login                -> ok (token {len(token)} chars)")

            auth = {"Authorization": f"Bearer {token}"}

            status = await api.get(
                "/api/v1/auth/registration-status", headers=auth
            )
            print(
                f"  registration-status           -> {status.status_code} {status.text}"
            )

            reg = await api.post(
                "/api/v1/auth/register",
                headers=auth,
                json={"name": name, "role": role},
            )
            print(f"  register                      -> {reg.status_code} {reg.text[:90]}")
            if reg.status_code != 200:
                failures += 1
                continue

            me = await api.get("/api/v1/auth/me", headers=auth)
            print(f"  auth/me                       -> {me.status_code} {me.text[:90]}")
            if me.status_code != 200:
                failures += 1

            for path, params in ROLE_CHECKS[role]:
                resp = await api.get(path, headers=auth, params=params)
                marker = "ok " if resp.status_code == 200 else "ERR"
                print(
                    f"  {marker} {path:30s} -> {resp.status_code} {resp.text[:70]}"
                )
                if resp.status_code != 200:
                    failures += 1

    print()
    if failures:
        print(f"{failures} check(s) failed.")
    else:
        print("All checks passed — the apps will be able to do this too.")
    return 1 if failures else 0


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--supabase", default=DEFAULT_SUPABASE)
    parser.add_argument("--api", default=DEFAULT_API)
    parser.add_argument(
        "--anon-key",
        default=os.environ.get("SUPABASE_ANON_KEY", ""),
        help="local stack anon key; also read from SUPABASE_ANON_KEY",
    )
    args = parser.parse_args()

    if not args.anon_key:
        print(
            "Need the local anon key. Pass --anon-key or set SUPABASE_ANON_KEY.\n"
            "Get it with: npx supabase status -o env",
            file=sys.stderr,
        )
        raise SystemExit(2)

    raise SystemExit(asyncio.run(run(args.supabase, args.api, args.anon_key)))


if __name__ == "__main__":
    main()
