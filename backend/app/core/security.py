"""Password hashing (Argon2id) and JWT issuing/verification.

- Passwords are hashed with Argon2id via argon2-cffi (never stored in
  plaintext, no reversible encoding).
- Access and refresh tokens are JWTs signed with HS256 using SECRET_KEY, with
  `aud`/`iss` claims to prevent cross-use of tokens between flows.
- Refresh-token rotation: the server stores a hash of every issued refresh
  token and its family id; reuse of an already-rotated token revokes the whole
  family (standard theft-detection behaviour).
"""

from __future__ import annotations

import hashlib
import secrets
from datetime import datetime, timedelta, timezone

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError, VerificationError, InvalidHashError

from app.core.config import get_settings

hasher = PasswordHasher()  # argon2id with library defaults (64MiB, t=3, p=4)


def hash_password(password: str) -> str:
    return hasher.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return hasher.verify(password_hash, password)
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False


ISSUER = "moodly"
AUD_ACCESS = "moodly:access"
AUD_REFRESH = "moodly:refresh"


def _now() -> datetime:
    return datetime.now(timezone.utc)


def issue_access_token(user_id: int) -> str:
    settings = get_settings()
    expires = timedelta(minutes=settings.access_token_minutes)
    payload = {
        "sub": str(user_id),
        "iss": ISSUER,
        "aud": AUD_ACCESS,
        "typ": "access",
        "iat": _now(),
        "exp": _now() + expires,
        "jti": secrets.token_hex(8),
    }
    return jwt.encode(
        payload,
        settings.secret_key or "",
        algorithm="HS256",
        headers={"kid": "moodly-1"},
    )


def issue_refresh_token(user_id: int, family_id: str = "") -> tuple[str, str, str]:
    """Return (token, jti, family_id) for a rotated refresh token."""
    settings = get_settings()
    family = family_id or secrets.token_hex(16)
    expires = timedelta(days=settings.refresh_token_days)
    jti = secrets.token_hex(16)
    payload = {
        "sub": str(user_id),
        "iss": ISSUER,
        "aud": AUD_REFRESH,
        "typ": "refresh",
        "iat": _now(),
        "exp": _now() + expires,
        "jti": jti,
        "fam": family,
    }
    token = jwt.encode(
        payload,
        settings.secret_key or "",
        algorithm="HS256",
        headers={"kid": "moodly-1"},
    )
    return token, jti, family


def decode_token(token: str, expected_type: str) -> dict[str, Any]:
    """Decode/verify a JWT and enforce its type.

    Raises `jwt.PyJWTError` subclasses on failure; callers translate into the
    appropriate 401 response.
    """
    settings = get_settings()
    audience = AUD_ACCESS if expected_type == "access" else AUD_REFRESH
    payload = jwt.decode(
        token,
        settings.secret_key or "",
        algorithms=["HS256"],
        audience=audience,
        issuer=ISSUER,
        options={"require": ["exp", "sub", "aud", "iss", "jti", "typ"]},
    )
    if payload.get("typ") != expected_type:
        raise jwt.InvalidTokenError(f"wrong token type: {payload.get('typ')}")
    return payload


def token_hash(token: str) -> str:
    """One-way hash used to persist refresh/reset tokens at rest."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()
