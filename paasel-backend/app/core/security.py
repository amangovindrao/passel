"""Supabase JWT verification — no custom token issuance.

Supabase signs access tokens two different ways depending on the project:

* **Asymmetric (ES256/RS256)** — current default. The token carries a `kid` and
  is verified against the project's published JWKS. The private key never
  leaves Supabase, so there is no shared secret to leak.
* **Symmetric (HS256)** — legacy. Verified with the project's JWT secret.

Both are accepted here. A backend that only handled HS256 would reject every
token from a modern project, which looks like a login bug and isn't one.
"""

import threading

import jwt
from jwt import PyJWKClient

from app.core.config import settings

_ASYMMETRIC_ALGORITHMS = ("ES256", "RS256", "ES512", "RS512")

# One client per process. It caches the fetched keys, so a normal request does
# no network I/O; a token with an unseen `kid` triggers a refresh, which is how
# Supabase key rotation is picked up without a redeploy.
_jwks_client: PyJWKClient | None = None
_jwks_lock = threading.Lock()


def _jwks_url() -> str:
    return f"{str(settings.supabase_url).rstrip('/')}/auth/v1/.well-known/jwks.json"


def _get_jwks_client() -> PyJWKClient:
    global _jwks_client
    if _jwks_client is None:
        with _jwks_lock:
            if _jwks_client is None:
                _jwks_client = PyJWKClient(
                    _jwks_url(),
                    cache_keys=True,
                    lifespan=600,
                )
    return _jwks_client


def reset_jwks_cache() -> None:
    """Drop the cached signing keys. For tests, and after a config change."""
    global _jwks_client
    with _jwks_lock:
        _jwks_client = None


def verify_supabase_token(token: str) -> dict:
    """Decode and verify a Supabase-issued JWT.

    Returns the full payload on success.
    Raises jwt.InvalidTokenError on any failure.
    """
    try:
        algorithm = jwt.get_unverified_header(token).get("alg")
    except jwt.DecodeError as exc:
        raise jwt.InvalidTokenError("Malformed token") from exc

    if algorithm in _ASYMMETRIC_ALGORITHMS:
        payload = _verify_asymmetric(token, algorithm)
    elif algorithm == "HS256":
        payload = _verify_symmetric(token)
    else:
        raise jwt.InvalidTokenError(f"Unsupported algorithm: {algorithm}")

    if not payload.get("sub"):
        raise jwt.InvalidTokenError("Missing sub claim")
    return payload


def _verify_asymmetric(token: str, algorithm: str) -> dict:
    try:
        signing_key = _get_jwks_client().get_signing_key_from_jwt(token)
    except jwt.PyJWKClientError as exc:
        # Unreachable or unusable JWKS. Surfaced as an invalid token because
        # that is what it means for this request: we cannot prove the caller.
        raise jwt.InvalidTokenError(f"Cannot resolve signing key: {exc}") from exc

    return jwt.decode(
        token,
        signing_key.key,
        algorithms=[algorithm],
        audience="authenticated",
        issuer=settings.supabase_issuer,
    )


def _verify_symmetric(token: str) -> dict:
    return jwt.decode(
        token,
        settings.supabase_jwt_secret,
        algorithms=["HS256"],
        audience="authenticated",
        issuer=settings.supabase_issuer,
    )
