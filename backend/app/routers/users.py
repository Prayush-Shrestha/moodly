"""Account endpoints: profile, consents, and account deletion. All private."""

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from app.core.deps import get_db, require_current_user
from app.core.rate_limit import limit_auth
from app.db.base import User
from app.schemas.auth import ConsentUpdate, ProfileUpdate, UserResponse
from app.services import auth_service

router = APIRouter(prefix="/me", tags=["account"])


@router.get("", response_model=UserResponse, summary="Current account profile")
def me(current_user: User = Depends(require_current_user)) -> UserResponse:
    return UserResponse.from_user(current_user)


@router.patch(
    "",
    response_model=UserResponse,
    summary="Update display name and/or privacy consents",
)
def update_me(
    payload: ProfileUpdate | ConsentUpdate,
    current_user: User = Depends(require_current_user),
    db: Session = Depends(get_db),
) -> UserResponse:
    if isinstance(payload, ProfileUpdate):
        if payload.display_name is not None:
            current_user.display_name = payload.display_name
    else:
        if payload.journal_upload_consent is not None:
            current_user.journal_upload_consent = payload.journal_upload_consent
        if payload.cloud_sync_consent is not None:
            current_user.cloud_sync_consent = payload.cloud_sync_consent
    db.commit()
    return UserResponse.from_user(current_user)


@router.delete(
    "",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete the account and every private record permanently",
)
def delete_account(
    request: Request,
    current_user: User = Depends(require_current_user),
    db: Session = Depends(get_db),
) -> None:
    limit_auth(request)
    auth_service.delete_account(db, current_user.id)
