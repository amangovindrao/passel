"""Decode a live Supabase token and compare it against what the backend expects.

Diagnoses the two things that usually make a genuine token look invalid: a
signing algorithm the backend does not accept, and an issuer that does not match
what it was configured with.

    python scripts/inspect_token.py --anon-key <key>
"""

from __future__ import annotations

import argparse
import asyncio
import json

import httpx
import jwt

from app.core.config import settings


async def main(supabase_url: str, anon_key: str, phone: str) -> None:
    async with httpx.AsyncClient(base_url=supabase_url, timeout=20) as client:
        headers = {"apikey": anon_key, "Content-Type": "application/json"}
        await client.post("/auth/v1/otp", headers=headers, json={"phone": phone})
        verified = await client.post(
            "/auth/v1/verify",
            headers=headers,
            json={"type": "sms", "phone": phone, "token": "123456"},
        )
        verified.raise_for_status()
        token = verified.json()["access_token"]

    header = jwt.get_unverified_header(token)
    claims = jwt.decode(token, options={"verify_signature": False})

    print("--- token as issued ---")
    print(f"alg      : {header.get('alg')}")
    print(f"kid      : {header.get('kid')}")
    print(f"iss      : {claims.get('iss')}")
    print(f"aud      : {claims.get('aud')}")
    print(f"sub      : {claims.get('sub')}")
    print(f"phone    : {claims.get('phone')}")
    print(f"role     : {claims.get('role')}")

    print("\n--- backend expects ---")
    print(f"issuer   : {settings.supabase_issuer}")
    print("algs     : ['HS256']")
    print("audience : authenticated")

    print("\n--- verification ---")
    try:
        jwt.decode(
            token,
            settings.supabase_jwt_secret,
            algorithms=["HS256"],
            audience="authenticated",
            issuer=settings.supabase_issuer,
        )
        print("OK — the backend accepts this token")
    except Exception as exc:  # noqa: BLE001 — this is a diagnostic
        print(f"REJECTED: {type(exc).__name__}: {exc}")

        # Narrow it down so the fix is obvious.
        try:
            jwt.decode(
                token,
                settings.supabase_jwt_secret,
                algorithms=["HS256"],
                options={"verify_aud": False, "verify_iss": False},
            )
            print("  -> signature and secret are FINE; issuer or audience is wrong")
        except Exception as inner:  # noqa: BLE001
            print(f"  -> signature check itself fails: {type(inner).__name__}: {inner}")

    print("\nfull claims:")
    print(json.dumps(claims, indent=2, default=str))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--supabase", default="http://127.0.0.1:54321")
    parser.add_argument("--anon-key", required=True)
    parser.add_argument("--phone", default="+919900000001")
    args = parser.parse_args()
    asyncio.run(main(args.supabase, args.anon_key, args.phone))
