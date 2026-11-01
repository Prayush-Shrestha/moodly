"""Authentication endpoints: register, login, token refresh, logout and the
password-reset flow. Auth endpoints are rate limited per client IP.
"""

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from app.core.deps import get_db, require_current_user
from app.core.rate_limit import limit_auth
from app.db.base import User
from app.schemas.auth import (
    AuthPayload,
    ForgotPasswordRequest,
    LoginRequest,
    RefreshRequest,
    RegisterRequest,
    ResetPasswordRequest,
    TokenPair,
)
from app.services import auth_service
from app.services.auth_service import AuthError, ConflictError

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post(
    "/register",
    response_model=AuthPayload,
    status_code=status.HTTP_201_CREATED,
    summary="Create an account and receive tokens",
)
def register(payload: RegisterRequest, request: Request, db: Session = Depends(get_db)) -> AuthPayload:
    limit_auth(request)
    try:
        return auth_service.register(db, payload)
    except ConflictError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=exc.message)


@router.post(
    "/login",
    response_model=AuthPayload,
    summary="Sign in with email + password",
)
def login(payload: LoginRequest, request: Request, db: Session = Depends(get_db)) -> AuthPayload:
    limit_auth(request)
    try:
        return auth_service.login(db, payload)
    except AuthError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(exc))


@router.post(
    "/refresh",
    response_model=TokenPair,
    summary="Exchange a refresh token for a new token pair (rotation)",
    description=(
        "Refresh tokens rotate on every use. Reusing an already-rotated token "
        "revokes its whole session family and returns 401."
    ),
)
def refresh(payload: RefreshRequest, request: Request, db: Session = Depends(get_db)) -> TokenPair:
    limit_auth(request)
    try:
        return auth_service.rotate_refresh(db, payload.refresh_token)
    except AuthError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(exc))


@router.post(
    "/logout",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Revoke the presented refresh token",
)
def logout(
    payload: RefreshRequest,
    request: Request,
    current_user: User = Depends(require_current_user),
    db: Session = Depends(get_db),
) -> None:
    limit_auth(request)
    auth_service.logout(db, payload.refresh_token, user_id=current_user.id)


@router.post(
    "/forgot-password",
    status_code=status.HTTP_200_OK,
    summary="Request a password-reset token (intent-revealing-safe)",
    description=(
        "Responds 200 regardless of whether the email exists. Without an email "
        "provider configured the reset link cannot be delivered; in dev mode "
        "(MOODLY_DEV_MODE=1) the token is returned so the flow can be tested."
    ),
)
def forgot_password(payload: ForgotPasswordRequest, request: Request, db: Session = Depends(get_db)):
    limit_auth(request)
    result = auth_service.forgot_password(db, payload.email)
    if result:
        return {"is_dev": True, **result}
    return {
        "is_dev": False,
        "detail": "If an account exists for this email, a reset link has been sent.",
    }


@router.post(
    "/reset-password",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Set a new password using a reset token (signs out everywhere)",
)
def reset_password(payload: ResetPasswordRequest, request: Request, db: Session = Depends(get_db)) -> None:
    limit_auth(request)
    try:
        auth_service.reset_password(db, payload.token, payload.password)
    except AuthError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))
