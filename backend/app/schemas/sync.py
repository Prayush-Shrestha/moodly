"""Data models exchanged with the mobile client for cloud sync.

client_id: stable identifier generated on the device; prevents duplicates.
conflict semantics: server wins only when its copy is strictly newer — the
client is then told exactly which rows to merge; nothing is silently lost.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

ValidMood = Literal["great", "good", "okay", "low", "terrible"]
VALID_EMOTIONS = {
    "calm", "happy", "excited", "grateful", "motivated",
    "tired", "stressed", "anxious", "sad", "angry",
}


class MoodEntryIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    client_id: str = Field(min_length=8, max_length=64)
    date: str = Field(pattern=r"^\d{4}-\d{2}-\d{2}$")
    mood: ValidMood
    emotions: list[str] = Field(default_factory=list, max_length=10)
    energy: int = Field(ge=1, le=5)
    note: str | None = Field(default=None, max_length=2000)
    updated_at: datetime
    is_deleted: bool = False

    @field_validator("emotions")
    @classmethod
    def _emotions(cls, values: list[str]) -> list[str]:
        cleaned: list[str] = []
        for value in values:
            v = value.strip().lower()
            if v not in VALID_EMOTIONS:
                raise ValueError(f"Unknown emotion: {value!r}")
            if v not in cleaned:
                cleaned.append(v)
        return cleaned


class JournalEntryIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    client_id: str = Field(min_length=8, max_length=64)
    date: str = Field(pattern=r"^\d{4}-\d{2}-\d{2}$")
    title: str | None = Field(default=None, max_length=200)
    body: str = Field(min_length=1, max_length=20000)
    updated_at: datetime
    is_deleted: bool = False


class SyncPushRequest(BaseModel):
    """One push per sync attempt. Journal rows are accepted ONLY when the
    request explicitly declares the user's journal-upload consent — the
    backend re-checks the account's stored consent too."""

    model_config = ConfigDict(extra="forbid")

    moods: list[MoodEntryIn] = Field(default_factory=list, max_length=500)
    journals: list[JournalEntryIn] = Field(default_factory=list, max_length=500)
    journal_upload_consent: bool = False


class MoodEntryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    client_id: str
    date: str
    mood: str
    emotions: str
    energy: int
    note: str | None
    is_deleted: bool
    server_updated_at: datetime


class JournalEntrySummary(BaseModel):
    """Never includes the body — bodies are only pulled explicitly."""

    model_config = ConfigDict(from_attributes=True)

    client_id: str
    date: str
    title: str | None
    body: str
    is_deleted: bool
    server_updated_at: datetime


class SyncConflict(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    client_id: str
    server_version: MoodEntryOut | JournalEntrySummary


class SyncPushResponse(BaseModel):
    accepted_moods: list[str]
    accepted_journals: list[str]
    mood_conflicts: list[SyncConflict]
    journal_conflicts: list[SyncConflict]
    journal_rejected_missing_consent: list[str]
    server_time: datetime
    cursor: str  # opaque ISO timestamp marking this push's server state


class SyncPullRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    cursor: str | None = Field(default=None, max_length=64)


class SyncPullResponse(BaseModel):
    moods: list[MoodEntryOut]
    journals: list[JournalEntrySummary]
    server_time: datetime
    cursor: str
