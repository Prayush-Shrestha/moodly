"""Rate-limit behaviour for auth and AI scopes."""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.core.config import get_settings

from tests.conftest import auth_headers, register


def test_auth_endpoint_rate_limit(client: TestClient) -> None:
    settings = get_settings()
    settings.auth_requests_per_minute = 3
    try:
        statuses = [
            client.post(
                "/auth/login",
                json={"email": "nobody@moodly.test", "password": "passw0rd1"},
            ).status_code
            for _ in range(5)
        ]
        # First requests pass (401 for bad creds), then the limiter kicks in.
        assert statuses[0] == 401
        assert 429 in statuses
        limited = [
            client.post(
                "/auth/login",
                json={"email": "nobody@moodly.test", "password": "passw0rd1"},
            )
            for _ in range(2)
        ]
        over_limit = next(r for r in limited if r.status_code == 429)
        assert over_limit.headers.get("retry-after")
    finally:
        settings.auth_requests_per_minute = 20


def test_ai_endpoint_rate_limit_per_user(client: TestClient) -> None:
    settings = get_settings()
    settings.ai_requests_per_minute = 2
    try:
        payload = register(client)
        headers = auth_headers(payload)
        body = {
            "journal_body": "A long and thoughtful journal entry about my day.",
            "entry_date": "2026-10-30",
            "consent_given": True,
        }
        statuses = [
            client.post("/ai/reflection", headers=headers, json=body).status_code
            for _ in range(4)
        ]
        assert statuses[:2] == [200, 200]
        assert 429 in statuses[2:]
    finally:
        settings.ai_requests_per_minute = 15


def test_disabled_limiter_allows_burst(client: TestClient) -> None:
    settings = get_settings()
    settings.rate_limit_enabled = False
    try:
        payload = register(client)
        headers = auth_headers(payload)
        body = {
            "journal_body": "Another thoughtful journal entry for the burst test.",
            "entry_date": "2026-10-30",
            "consent_given": True,
        }
        statuses = [
            client.post("/ai/reflection", headers=headers, json=body).status_code
            for _ in range(20)
        ]
        assert set(statuses) == {200}
    finally:
        settings.rate_limit_enabled = True
