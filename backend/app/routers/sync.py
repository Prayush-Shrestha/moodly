"""Synchronization endpoints (authenticated, per-user, rate limited).

Data isolation: every query is scoped to the authenticated user id — there is
no route shape that can read another account's records.
"""

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from app.core.deps import get_db, require_current_user
from app.core.rate_limit import limit_auth
from app.db.base import User
from app.schemas.sync import (
    SyncPullRequest,
    SyncPullResponse,
    SyncPushRequest,
    SyncPushResponse,
)
from app.services import sync_service

router = APIRouter(prefix="/sync", tags=["sync"])


@router.post(
    "/push",
    response_model=SyncPushResponse,
    summary="Upload local changes (moods always; journals only with consent)",
    description=(
        "Upserts rows keyed by client_id. Conflicts are returned with the "
        "server version — nothing is silently overwritten. Journal rows are "
        "rejected (and listed under journal_rejected_missing_consent) unless "
        "both the request and the account carry journal-upload consent."
    ),
)
def push(
    payload: SyncPushRequest,
    request: Request,
    user: User = Depends(require_current_user),
    db: Session = Depends(get_db),
) -> SyncPushResponse:
    limit_auth(request)
    return sync_service.push(
        db,
        user,
        moods=payload.moods,
        journals=payload.journals,
        journal_upload_consent=payload.journal_upload_consent,
    )


@router.post(
    "/pull",
    response_model=SyncPullResponse,
    summary="Download changes since a cursor",
    description="Returns this account's rows updated after the given cursor.",
)
def pull(
    payload: SyncPullRequest,
    request: Request,
    user: User = Depends(require_current_user),
    db: Session = Depends(get_db),
) -> SyncPullResponse:
    limit_auth(request)
    return sync_service.pull(db, user, cursor=payload.cursor)
