"""Pytest fixtures: disposable per-test database + FastAPI test client.

Every test gets its own temp-file SQLite database with a fresh engine, so
tests are isolated and never touch the real backend database. Set the
MOODLY_TESTING env flag before importing the app (done at module import here).
"""

from __future__ import annotations

import os
import tempfile
from collections.abc import Iterator
from pathlib import Path

os.environ.setdefault("MOODLY_TESTING", "1")
os.environ.setdefault("MOODLY_DEV_MODE", "1")
os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")
os.environ.setdefault("RATE_LIMIT_ENABLED", "1")

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import create_engine  # noqa: E402

from app.core import rate_limit  # noqa: E402
from app.core.config import get_settings  # noqa: E402
from app.db import session as db_session  # noqa: E402
from app.db.session import Base  # noqa: E402
from app.main import create_app  # noqa: E402
import app.db.base  # noqa: E402,F401


@pytest.fixture()
def client(tmp_path: Path) -> Iterator[TestClient]:
    db_file = tmp_path / "test.db"
    engine = create_engine(
        f"sqlite:///{db_file}",
        connect_args={"check_same_thread": False},
        future=True,
    )
    db_session.set_engine(engine)
    Base.metadata.create_all(bind=engine)
    rate_limit.reset_rate_limiter()
    # Generous limits by default; the rate-limit test lowers these explicitly.
    settings = get_settings()
    settings.rate_limit_enabled = True
    settings.ai_requests_per_minute = 15
    settings.auth_requests_per_minute = 20

    app = create_app()
    with TestClient(app, raise_server_exceptions=False) as test_client:
        yield test_client

    db_session.set_engine(engine)
    engine.dispose()


def register(client: TestClient, email: str = "user@moodly.test", password: str = "passw0rd1") -> dict:
    response = client.post(
        "/auth/register",
        json={"email": email, "password": password, "display_name": "Test"},
    )
    assert response.status_code == 201, response.text
    return response.json()


def auth_headers(payload: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {payload['access_token']}"}
