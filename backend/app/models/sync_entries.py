"""Cloud copies of mood/journal entries for synchronization.

Design: rows are keyed by (user_id, client_id) where client_id is generated on
the device when a row is first synced. This keeps identity stable across sync
and prevents duplicates no matter which device writes first.

Soft delete is implemented with `is_deleted` tombstones so other devices can
learn about deletions. Deleted rows are kept for the sync window (they are
excluded from all data-isolation-sensitive queries).
"""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.models.user import utcnow


class MoodEntryRecord(Base):
    __tablename__ = "mood_entries"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(index=True)
    client_id: Mapped[str] = mapped_column(String(64))
    # yyyy-MM-dd in the USER's local calendar (client decides the day).
    date: Mapped[str] = mapped_column(String(10))
    mood: Mapped[str] = mapped_column(String(16))
    emotions: Mapped[str] = mapped_column(Text, default="")
    energy: Mapped[int] = mapped_column(Integer)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )
    server_updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )

    __table_args__ = (
        UniqueConstraint("user_id", "client_id", name="uq_mood_user_client"),
        Index("ix_mood_user_updated", "user_id", "server_updated_at"),
        Index("ix_mood_user_date", "user_id", "date"),
    )


class JournalEntryRecord(Base):
    __tablename__ = "journal_entries"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(index=True)
    client_id: Mapped[str] = mapped_column(String(64))
    date: Mapped[str] = mapped_column(String(10))
    title: Mapped[str | None] = mapped_column(String(200), nullable=True)
    body: Mapped[str] = mapped_column(Text)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )
    server_updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )

    __table_args__ = (
        UniqueConstraint("user_id", "client_id", name="uq_journal_user_client"),
        Index("ix_journal_user_updated", "user_id", "server_updated_at"),
    )
