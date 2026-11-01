"""Typed configuration loaded from environment variables / a `.env` file.

Secrets are read **only** from the environment — never hardcoded. When a value
is missing the app starts with safe local defaults but either disables the
related feature (AI) or, for SECRET_KEY, refuses to start unless dev mode is
explicitly enabled, so tests remain reproducible.
"""

from __future__ import annotations

import secrets
import os
import sys
from functools import lru_cache

from pydantic import BaseModel, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

ENV_FILE = os.path.join(
    os.path.dirname(  # backend/app/core/  -> backend/app/  -> backend/
        os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ),
    ".env",
)


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=ENV_FILE,
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    # --- Database -------------------------------------------------------------
    # Defaults to a local SQLite file so the backend is runnable without any
    # external credentials. For production use PostgreSQL (see README).
    database_url: str = "sqlite:///./moodly_backend.db"

    # --- Security -------------------------------------------------------------
    secret_key: str | None = None
    access_token_minutes: int = 30
    refresh_token_days: int = 30
    dev_mode: bool = Field(default=False, alias="MOODLY_DEV_MODE")

    # --- CORS -----------------------------------------------------------------
    cors_origins: str = "http://localhost:5173"

    # --- Rate limiting --------------------------------------------------------
    rate_limit_enabled: bool = True
    ai_requests_per_minute: int = 15
    auth_requests_per_minute: int = 20

    # --- AI provider ----------------------------------------------------------
    openai_api_key: str | None = None
    openai_model: str = "gpt-4o-mini"
    openai_base_url: str = "https://api.openai.com/v1"
    openai_timeout_seconds: int = 30

    # --- Logging --------------------------------------------------------------
    log_level: str = "INFO"

    @field_validator("access_token_minutes", "refresh_token_days")
    @classmethod
    def _positive(cls, v: int) -> int:
        if v <= 0:
            raise ValueError("token lifetimes must be positive")
        if v > 365 * 24 * 60:
            raise ValueError("token lifetime too long")
        return v

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @property
    def ai_enabled(self) -> bool:
        """True only when a provider key is actually configured."""
        return bool(self.openai_api_key and self.openai_api_key.strip())

    @property
    def is_testing_env(self) -> bool:
        return os.environ.get("MOODLY_TESTING", "").strip().lower() in {"1", "true", "yes"}

    def ensure_safe_startup(self) -> None:
        """Refuse to run with an insecure configuration outside dev mode.

        In development mode (dev_mode=True) a random secret is generated for
        convenience and warned about. Tests set MOODLY_TESTING which generates
        a deterministic fresh key per process.
        """
        if not self.secret_key or self.secret_key.strip() == "" or self._is_placeholder(self.secret_key):
            if self.dev_mode or self.is_testing_env:
                self.secret_key = secrets.token_hex(32)
                warning(
                    "SECRET_KEY missing — generated a temporary random key. "
                    "Restarting will invalidate tokens. Set SECRET_KEY in production."
                )
            else:
                raise RuntimeError(
                    "SECRET_KEY is not set. Generate one with "
                    '`python -c "import secrets; print(secrets.token_hex(32))"` '
                    "and put it in your .env file. This guard keeps production "
                    "tokens secure."
                )

    @staticmethod
    def _is_placeholder(value: str) -> bool:
        return value.strip().upper().startswith("CHANGE_ME")


def warning(message: str) -> None:
    print(f"[config] {message}", file=sys.stderr)


@lru_cache
def get_settings() -> Settings:
    settings = Settings()
    settings.ensure_safe_startup()
    return settings
