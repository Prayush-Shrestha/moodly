"""Cloud synchronization service.

Conflict rules (never silently overwrite newer user data):
- Rows are identified by `(user_id, client_id)` — no duplicates ever, no
  matter which device writes first.
- An incoming row replaces the stored copy ONLY when the stored copy's client
  `updated_at` is not strictly newer than the incoming one. Otherwise the row
  is returned as a conflict with the full server version so the client can
  merge/keep-newest locally. (`server_updated_at` is only used for pull
  cursors — never for conflict decisions.)
- Deletes are soft (tombstones) and follow the same recency rule; deleted rows
  are excluded from all other reads.

Journal rows are accepted ONLY when the request asserts the user's
journal-upload consent AND the account has that consent stored (double gate —
the app's consent screen and the account record must agree).
"""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.logging import get_logger
from app.db.base import JournalEntryRecord, MoodEntryRecord, User
from app.models.user import utcnow
from app.schemas.sync import (
    JournalEntryIn,
    JournalEntrySummary,
    MoodEntryIn,
    MoodEntryOut,
    SyncConflict,
    SyncPullResponse,
    SyncPushResponse,
)

log = get_logger("moodly.sync")

_BATCH_LIMIT = 500


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def push(
    db: Session,
    user: User,
    moods: list[MoodEntryIn],
    journals: list[JournalEntryIn],
    journal_upload_consent: bool,
) -> SyncPushResponse:
    accepted_moods: list[str] = []
    accepted_journals: list[str] = []
    mood_conflicts: list[SyncConflict] = []
    journal_conflicts: list[SyncConflict] = []
    journal_rejected: list[str] = []

    journal_allowed = (
        journal_upload_consent and bool(user.journal_upload_consent)
    )

    for mood in moods[:_BATCH_LIMIT]:
        if _upsert_mood(db, user.id, mood):
            accepted_moods.append(mood.client_id)
        else:
            existing = db.scalar(
                select(MoodEntryRecord).where(
                    MoodEntryRecord.user_id == user.id,
                    MoodEntryRecord.client_id == mood.client_id,
                )
            )
            if existing is not None:
                mood_conflicts.append(
                    SyncConflict(
                        client_id=mood.client_id,
                        server_version=_mood_out(existing),
                    )
                )

    for journal in journals[:_BATCH_LIMIT]:
        if not journal_allowed:
            journal_rejected.append(journal.client_id)
            continue
        if _upsert_journal(db, user.id, journal):
            accepted_journals.append(journal.client_id)
        else:
            existing = db.scalar(
                select(JournalEntryRecord).where(
                    JournalEntryRecord.user_id == user.id,
                    JournalEntryRecord.client_id == journal.client_id,
                )
            )
            if existing is not None:
                journal_conflicts.append(
                    SyncConflict(
                        client_id=journal.client_id,
                        server_version=_journal_out(existing),
                    )
                )

    db.commit()
    server_time = utcnow()
    return SyncPushResponse(
        accepted_moods=accepted_moods,
        accepted_journals=accepted_journals,
        mood_conflicts=mood_conflicts,
        journal_conflicts=journal_conflicts,
        journal_rejected_missing_consent=journal_rejected,
        server_time=server_time,
        cursor=server_time.isoformat(),
    )


def _upsert_mood(db: Session, user_id: int, mood: MoodEntryIn) -> bool:
    existing = db.scalar(
        select(MoodEntryRecord).where(
            MoodEntryRecord.user_id == user_id,
            MoodEntryRecord.client_id == mood.client_id,
        )
    )
    incoming_ts = _as_utc(mood.updated_at)
    if existing is None:
        db.add(
            MoodEntryRecord(
                user_id=user_id,
                client_id=mood.client_id,
                date=mood.date,
                mood=mood.mood,
                emotions=",".join(mood.emotions),
                energy=mood.energy,
                note=mood.note,
                is_deleted=mood.is_deleted,
                created_at=incoming_ts,
                updated_at=incoming_ts,
                server_updated_at=utcnow(),
            )
        )
        return True

    if _as_utc(existing.updated_at) > incoming_ts:
        return False  # stored client edit is newer → conflict for the client

    existing.date = mood.date
    existing.mood = mood.mood
    existing.emotions = ",".join(mood.emotions)
    existing.energy = mood.energy
    existing.note = mood.note
    existing.is_deleted = mood.is_deleted
    existing.updated_at = incoming_ts
    existing.server_updated_at = utcnow()
    return True


def _upsert_journal(db: Session, user_id: int, journal: JournalEntryIn) -> bool:
    existing = db.scalar(
        select(JournalEntryRecord).where(
            JournalEntryRecord.user_id == user_id,
            JournalEntryRecord.client_id == journal.client_id,
        )
    )
    incoming_ts = _as_utc(journal.updated_at)
    if existing is None:
        db.add(
            JournalEntryRecord(
                user_id=user_id,
                client_id=journal.client_id,
                date=journal.date,
                title=journal.title,
                body=journal.body,
                is_deleted=journal.is_deleted,
                created_at=incoming_ts,
                updated_at=incoming_ts,
                server_updated_at=utcnow(),
            )
        )
        return True

    if _as_utc(existing.updated_at) > incoming_ts:
        return False

    existing.date = journal.date
    existing.title = journal.title
    existing.body = journal.body
    existing.is_deleted = journal.is_deleted
    existing.updated_at = incoming_ts
    existing.server_updated_at = utcnow()
    return True


def pull(db: Session, user: User, cursor: str | None) -> SyncPullResponse:
    """Return every row for this user updated since `cursor` (opaque ISO ts)."""
    query = select(MoodEntryRecord).where(MoodEntryRecord.user_id == user.id)
    journal_query = select(JournalEntryRecord).where(
        JournalEntryRecord.user_id == user.id
    )

    since: datetime | None = None
    if cursor:
        try:
            since = _as_utc(datetime.fromisoformat(cursor))
        except ValueError:
            since = None  # invalid cursor → full pull, never an error
    if since is not None:
        query = query.where(MoodEntryRecord.server_updated_at > since)
        journal_query = journal_query.where(JournalEntryRecord.server_updated_at > since)

    moods = db.scalars(query.order_by(MoodEntryRecord.server_updated_at)).all()
    journals = db.scalars(journal_query.order_by(JournalEntryRecord.server_updated_at)).all()

    server_time = utcnow()
    return SyncPullResponse(
        moods=[_mood_out(row) for row in moods[:_BATCH_LIMIT]],
        journals=[_journal_out(row) for row in journals[:_BATCH_LIMIT]],
        server_time=server_time,
        cursor=server_time.isoformat(),
    )


def _mood_out(row: MoodEntryRecord) -> MoodEntryOut:
    return MoodEntryOut(
        client_id=row.client_id,
        date=row.date,
        mood=row.mood,
        emotions=row.emotions,
        energy=row.energy,
        note=row.note,
        is_deleted=row.is_deleted,
        server_updated_at=row.server_updated_at,
    )


def _journal_out(row: JournalEntryRecord) -> JournalEntrySummary:
    return JournalEntrySummary(
        client_id=row.client_id,
        date=row.date,
        title=row.title,
        body=row.body,
        is_deleted=row.is_deleted,
        server_updated_at=row.server_updated_at,
    )
