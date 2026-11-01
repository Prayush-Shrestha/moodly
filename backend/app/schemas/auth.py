"""Auth request/response schemas. Failed auth is always generic on purpose:
the API never reveals whether an email is registered.
"""

from __future__ import annotations

import re

from pydantic import BaseModel, ConfigDict, Field, field_validator

_EMAIL_RE = re.compile(r"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$")
_NAME_RE = re.compile(r"^[\w][\w \-']{0,78}$")


class RegisterRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    email: str = Field(max_length=255)
    password: str = Field(min_length=8, max_length=128)
    display_name: str = Field(default="", max_length=80)

    @field_validator("email")
    @classmethod
    def _email(cls, v: str) -> str:
        v = v.strip().lower()
        if not _EMAIL_RE.match(v):
            raise ValueError("Enter a valid email address")
        return v

    @field_validator("password")
    @classmethod
    def _password_strength(cls, v: str) -> str:
        if not re.search(r"[A-Za-z]", v):
            raise ValueError("Password must contain a letter")
        if not re.search(r"\d", v):
            raise ValueError("Password must contain a digit")
        return v

    @field_validator("display_name")
    @classmethod
    def _name(cls, v: str) -> str:
        v = v.strip()
        if v and not _NAME_RE.match(v):
            raise ValueError("Name can contain letters, digits, spaces and -_')")
        return v


class LoginRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    email: str = Field(max_length=255)
    password: str = Field(min_length=1, max_length=128)

    @field_validator("email")
    @classmethod
    def _email(cls, v: str) -> str:
        return v.strip().lower()


class RefreshRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    refresh_token: str = Field(min_length=10, max_length=4096)


class ForgotPasswordRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    email: str = Field(max_length=255)

    @field_validator("email")
    @classmethod
    def _email(cls, v: str) -> str:
        v = v.strip().lower()
        if not _EMAIL_RE.match(v):
            raise ValueError("Enter a valid email address")
        return v


class ResetPasswordRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    token: str = Field(min_length=10, max_length=256)
    password: str = Field(min_length=8, max_length=128)

    @field_validator("password")
    @classmethod
    def _password_strength(cls, v: str) -> str:
        if not re.search(r"[A-Za-z]", v):
            raise ValueError("Password must contain a letter")
        if not re.search(r"\d", v):
            raise ValueError("Password must contain a digit")
        return v


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int  # access token lifetime in seconds


class DevResetToken(BaseModel):
    """Returned ONLY when dev mode is on and no mail provider is configured."""

    reset_token: str
    user_id: int
    is_dev: bool = True


class AuthPayload(TokenPair):
    user: "UserResponse"


class UserResponse(BaseModel):
    id: int
    email: str
    display_name: str
    journal_upload_consent: bool
    cloud_sync_consent: bool
    created_at: str

    @classmethod
    def from_user(cls, user: "object") -> "UserResponse":
        # user is an ORM User; keep this forward-compatible.
        return cls(
            id=user.id,
            email=user.email,
            display_name=user.display_name or "",
            journal_upload_consent=bool(user.journal_upload_consent),
            cloud_sync_consent=bool(user.cloud_sync_consent),
            created_at=user.created_at.isoformat(),
        )


class ConsentUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    journal_upload_consent: bool | None = None
    cloud_sync_consent: bool | None = None


class ProfileUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    display_name: str = Field(default=None, max_length=80)

    @field_validator("display_name")
    @classmethod
    def _name(cls, v: str | None) -> str | None:
        if v is None:
            return None
        v = v.strip()
        if v and not _NAME_RE.match(v):
            raise ValueError("Name can contain letters, digits, spaces and -_')")
        return v


AuthPayload.model_rebuild()
