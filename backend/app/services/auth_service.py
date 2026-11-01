"""Authentication and account management logic.

Security notes:
- Passwords are hashed with Argon2; plaintext is never stored or logged.
- Failed logins return a GENERIC message (no user enumeration).
- Refresh tokens rotate on every use; reuse of a rotated token revokes the
  entire token family (theft detection).
- Refresh / reset tokens are persisted only as sha256 hashes.
"""

from __future__ import annotations

import secrets
from datetime import datetime, timedelta, timezone

import jwt as pyjwt
from sqlalchemy import delete, select, update
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.logging import get_logger
from app.core.security import (
    decode_token,
    hash_password,
    issue_access_token,
    issue_refresh_token,
    token_hash,
    verify_password,
)
from app.db.base import (
    JournalEntryRecord,
    MoodEntryRecord,
    PasswordResetToken,
    RefreshToken,
    User,
)

from app.schemas.auth import (
    AuthPayload,
    LoginRequest,
    RegisterRequest,
    TokenPair,
    UserResponse,
)

log = get_logger("moodly.auth")

RESET_TOKEN_MINUTES = 30


class AuthError(Exception):
    """Invalid credentials/token; routers map this to HTTP 401."""


class ConflictError(Exception):
    def __init__(self, message: str) -> None:
        super().__init__(message)
        self.message = message


# --- token issuing ------------------------------------------------------------


def _store_refresh(db: Session, user: User, family_id: str | None = None) -> str:
    """Issue + persist a hashed refresh token; returns the raw token."""
    settings = get_settings()
    token, jti, family = issue_refresh_token(user.id, family_id or "")
    db.add(
        RefreshToken(
            user_id=user.id,
            token_hash=token_hash(token),
            family_id=family,
            jti=jti,
            expires_at=datetime.now(timezone.utc)
            + timedelta(days=settings.refresh_token_days),
        )
    )
    return token


def _issue_pair(db: Session, user: User) -> TokenPair:
    settings = get_settings()
    refresh_token = _store_refresh(db, user)
    return TokenPair(
        access_token=issue_access_token(user.id),
        refresh_token=refresh_token,
        expires_in=settings.access_token_minutes * 60,
    )


def _user_response(user: User) -> UserResponse:
    return UserResponse.from_user(user)


# --- flows --------------------------------------------------------------------


def register(db: Session, payload: RegisterRequest) -> AuthPayload:
    existing = db.scalar(select(User).where(User.email == payload.email))
    if existing is not None:
        raise ConflictError("An account with this email already exists")
    user = User(
        email=payload.email,
        password_hash=hash_password(payload.password),
        display_name=payload.display_name,
    )
    db.add(user)
    db.flush()
    tokens = _issue_pair(db, user)
    db.commit()
    log.info("user registered")
    return AuthPayload(**tokens.model_dump(), user=_user_response(user))


def login(db: Session, payload: LoginRequest) -> AuthPayload:
    user = db.scalar(select(User).where(User.email == payload.email))
    if user is None or not verify_password(payload.password, user.password_hash):
        # Generic failure message: never reveal which part was wrong.
        raise AuthError("Incorrect email or password")
    tokens = _issue_pair(db, user)
    db.commit()
    log.info("user login")
    return AuthPayload(**tokens.model_dump(), user=_user_response(user))


def rotate_refresh(db: Session, refresh_token: str) -> TokenPair:
    """Rotate a refresh token; reuse of a rotated token revokes its family."""
    try:
        payload = decode_token(refresh_token, expected_type="refresh")
    except pyjwt.PyJWTError as exc:
        raise AuthError("Invalid refresh token") from exc

    user_id = int(payload["sub"])
    jti = str(payload.get("jti"))
    row = db.scalar(select(RefreshToken).where(RefreshToken.jti == jti))
    if row is None or row.user_id != user_id:
        raise AuthError("Invalid refresh token")

    now = datetime.now(timezone.utc)

    if row.rotated or row.revoked:
        db.execute(
            update(RefreshToken)
            .where(RefreshToken.family_id == row.family_id)
            .values(revoked=True)
        )
        db.commit()
        log.warning("refresh token reuse detected")
        raise AuthError("Session revoked. Please sign in again.")

    if row.expires_at.replace(tzinfo=timezone.utc) < now:
        row.revoked = True
        db.commit()
        raise AuthError("Session expired. Please sign in again.")

    user = db.get(User, user_id)
    if user is None:
        raise AuthError("Invalid refresh token")

    row.rotated = True
    new_refresh = _store_refresh(db, user, family_id=row.family_id)
    settings = get_settings()
    db.commit()
    log.info("refresh rotated")
    return TokenPair(
        access_token=issue_access_token(user.id),
        refresh_token=new_refresh,
        expires_in=settings.access_token_minutes * 60,
    )


def logout(db: Session, refresh_token: str | None, user_id: int | None = None) -> None:
    if not refresh_token:
        return
    row = db.scalar(
        select(RefreshToken).where(RefreshToken.token_hash == token_hash(refresh_token))
    )
    if row is not None and (user_id is None or row.user_id == user_id):
        row.revoked = True
        db.commit()


def revoke_all_sessions(db: Session, user_id: int) -> None:
    db.execute(
        update(RefreshToken).where(RefreshToken.user_id == user_id).values(revoked=True)
    )


def forgot_password(db: Session, email: str) -> dict[str, object] | None:
    """Always non-revealing: response never says whether the account exists.

    Returns a dev-only reset token when dev mode is on and no mail provider is
    configured, so the flow is testable without SMTP infrastructure.
    """
    settings = get_settings()
    user = db.scalar(select(User).where(User.email == email))
    if user is None:
        log.info("password reset requested for unknown email")
        return None

    raw = secrets.token_urlsafe(32)
    db.add(
        PasswordResetToken(
            user_id=user.id,
            token_hash=token_hash(raw),
            expires_at=datetime.now(timezone.utc) + timedelta(minutes=RESET_TOKEN_MINUTES),
        )
    )
    db.commit()
    log.info("password reset token issued")

    if settings.dev_mode:
        return {"reset_token": raw, "user_id": user.id}
    return None


def reset_password(db: Session, raw_token: str, new_password: str) -> None:
    row = db.scalar(
        select(PasswordResetToken).where(
            PasswordResetToken.token_hash == token_hash(raw_token)
        )
    )
    now = datetime.now(timezone.utc)
    expired = (
        row is not None and row.expires_at.replace(tzinfo=timezone.utc) < now
    )
    used = row is not None and row.used_at is not None
    if row is None or expired or used:
        raise AuthError("Invalid or expired reset link")
    user = db.get(User, row.user_id)
    if user is None:
        raise AuthError("Invalid or expired reset link")
    user.password_hash = hash_password(new_password)
    row.used_at = now
    revoke_all_sessions(db, user.id)
    db.commit()
    log.info("password reset completed")


def delete_account(db: Session, user_id: int) -> None:
    """Delete the user account and every private row."""
    db.execute(delete(MoodEntryRecord).where(MoodEntryRecord.user_id == user_id))
    db.execute(delete(JournalEntryRecord).where(JournalEntryRecord.user_id == user_id))
    db.execute(delete(RefreshToken).where(RefreshToken.user_id == user_id))
    db.execute(delete(PasswordResetToken).where(PasswordResetToken.user_id == user_id))
    user = db.get(User, user_id)
    if user is not None:
        db.delete(user)
    db.commit()
    log.info("account deleted")
