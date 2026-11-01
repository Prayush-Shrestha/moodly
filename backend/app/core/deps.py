"""Shared FastAPI dependencies: DB session, current user, optional user, AI."""

from __future__ import annotations

from collections.abc import Iterator

from fastapi import Depends, Header, HTTPException, status
from sqlalchemy.orm import Session

import jwt as pyjwt

from app.core.security import decode_token
from app.db.base import User
from app.db.session import SessionFactory
from app.services.ai.service import ai_service


def get_db() -> Iterator[Session]:
    """Yield a database session that is always closed, even on error."""
    session = SessionFactory()
    try:
        yield session
    finally:
        session.close()


_BEARER_PREFIX = "bearer "


def _bearer_token(authorization: str | None) -> str:
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated",
            headers={"WWW-Authenticate": "Bearer"},
        )
    if not authorization.lower().startswith(_BEARER_PREFIX):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authorization header",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return authorization[len(_BEARER_PREFIX) :].strip()


def get_current_user_id(authorization: str | None = Header(default=None)) -> int:
    """Require a valid access token and return the user id (401 otherwise)."""
    token = _bearer_token(authorization)
    try:
        payload = decode_token(token, expected_type="access")
    except pyjwt.ExpiredSignatureError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token expired",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    except pyjwt.PyJWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    try:
        return int(payload["sub"])
    except (KeyError, TypeError, ValueError) as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token subject"
        ) from exc


def require_current_user(
    user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
) -> User:
    user = db.get(User, user_id)
    if user is None:
        # Token valid but account deleted.
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Account no longer exists"
        )
    return user


def get_ai_service() -> "object":  # returns AiService facade
    return ai_service
