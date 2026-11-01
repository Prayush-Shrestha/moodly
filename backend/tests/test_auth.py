"""Authentication, registration, validation, refresh rotation, password reset,
account deletion, and data-isolation tests."""

from __future__ import annotations

from fastapi.testclient import TestClient

from tests.conftest import auth_headers, register


# --- registration / validation ------------------------------------------------


def test_register_returns_tokens_and_user(client: TestClient) -> None:
    payload = register(client)
    assert payload["user"]["email"] == "user@moodly.test"
    assert payload["access_token"]
    assert payload["refresh_token"]
    assert payload["expires_in"] == 1800


def test_register_rejects_invalid_email(client: TestClient) -> None:
    response = client.post(
        "/auth/register", json={"email": "not-an-email", "password": "passw0rd1"}
    )
    assert response.status_code == 422
    # Field-level error, never echoing raw values.
    assert any("email" in e["field"] for e in response.json()["errors"])


def test_register_rejects_weak_password(client: TestClient) -> None:
    response = client.post(
        "/auth/register", json={"email": "a@b.co", "password": "alllettersonly"}
    )
    assert response.status_code == 422


def test_register_rejects_duplicate_email(client: TestClient) -> None:
    register(client)
    response = client.post(
        "/auth/register", json={"email": "user@moodly.test", "password": "passw0rd2"}
    )
    assert response.status_code == 409


def test_password_never_stored_in_plaintext(client: TestClient) -> None:
    register(client)
    from sqlalchemy import select

    from app.db.base import User
    from app.db.session import SessionFactory

    db = SessionFactory()
    try:
        user = db.scalar(select(User))
        assert user is not None
        assert "passw0rd1" not in user.password_hash
        assert user.password_hash.startswith("$argon2")
    finally:
        db.close()


# --- login --------------------------------------------------------------------


def test_login_with_wrong_password_is_generic_401(client: TestClient) -> None:
    register(client)
    response = client.post(
        "/auth/login", json={"email": "user@moodly.test", "password": "wrong9999"}
    )
    assert response.status_code == 401
    # Generic: does not reveal whether the email exists.
    assert "email" in response.json()["detail"].lower()


def test_login_unknown_email_returns_same_message(client: TestClient) -> None:
    response = client.post(
        "/auth/login", json={"email": "ghost@moodly.test", "password": "passw0rd1"}
    )
    assert response.status_code == 401
    assert response.json()["detail"] == "Incorrect email or password"


# --- protected endpoints ------------------------------------------------------


def test_protected_endpoints_require_token(client: TestClient) -> None:
    for method, path in [
        ("GET", "/me"),
        ("POST", "/ai/reflection"),
        ("POST", "/sync/push"),
        ("POST", "/sync/pull"),
    ]:
        body = {} if method == "POST" else None
        if path == "/ai/reflection":
            body = {"journal_body": "x", "entry_date": "2026-10-30", "consent_given": True}
        response = client.request(method, path, json=body)
        assert response.status_code == 401, path


def test_garbage_token_rejected(client: TestClient) -> None:
    response = client.get("/me", headers={"Authorization": "Bearer garbage.token.here"})
    assert response.status_code == 401


def test_access_token_rejected_as_refresh_token(client: TestClient) -> None:
    payload = register(client)
    response = client.post(
        "/auth/refresh", json={"refresh_token": payload["access_token"]}
    )
    assert response.status_code == 401


def test_me_updates_profile_and_consents(client: TestClient) -> None:
    payload = register(client)
    headers = auth_headers(payload)
    response = client.patch("/me", json={"display_name": "Renamed"}, headers=headers)
    assert response.status_code == 200
    assert response.json()["display_name"] == "Renamed"
    response = client.patch(
        "/me", json={"journal_upload_consent": True}, headers=headers
    )
    assert response.json()["journal_upload_consent"] is True


# --- refresh rotation ---------------------------------------------------------


def test_refresh_rotates_tokens(client: TestClient) -> None:
    payload = register(client)
    response = client.post(
        "/auth/refresh", json={"refresh_token": payload["refresh_token"]}
    )
    assert response.status_code == 200
    rotated = response.json()
    assert rotated["refresh_token"] != payload["refresh_token"]
    # The new access token works.
    me = client.get("/me", headers=auth_headers(rotated))
    assert me.status_code == 200


def test_refresh_token_reuse_revokes_family(client: TestClient) -> None:
    payload = register(client)
    first = client.post(
        "/auth/refresh", json={"refresh_token": payload["refresh_token"]}
    )
    assert first.status_code == 200
    # Replaying the OLD token = theft signal → revoke everything in the family.
    replay = client.post(
        "/auth/refresh", json={"refresh_token": payload["refresh_token"]}
    )
    assert replay.status_code == 401
    # The rotated token is dead too.
    after = client.post(
        "/auth/refresh", json={"refresh_token": first.json()["refresh_token"]}
    )
    assert after.status_code == 401


def test_logout_revokes_refresh_token(client: TestClient) -> None:
    payload = register(client)
    response = client.post(
        "/auth/logout",
        json={"refresh_token": payload["refresh_token"]},
        headers=auth_headers(payload),
    )
    assert response.status_code == 204
    after = client.post(
        "/auth/refresh", json={"refresh_token": payload["refresh_token"]}
    )
    assert after.status_code == 401


# --- password reset -----------------------------------------------------------


def test_forgot_password_never_reveals_account_existence(client: TestClient) -> None:
    register(client)
    known = client.post("/auth/forgot-password", json={"email": "user@moodly.test"})
    unknown = client.post("/auth/forgot-password", json={"email": "nobody@moodly.test"})
    assert known.status_code == unknown.status_code == 200
    # Both return the same envelope shape (dev flag may differ by config only).
    assert "is_dev" in known.json() and "is_dev" in unknown.json()


def test_reset_password_flow_signs_out_everywhere(client: TestClient) -> None:
    payload = register(client)
    forgot = client.post("/auth/forgot-password", json={"email": "user@moodly.test"})
    token = forgot.json()["reset_token"]
    reset = client.post(
        "/auth/reset-password", json={"token": token, "password": "brandNew99"}
    )
    assert reset.status_code == 204
    # Old sessions are revoked.
    old = client.post("/auth/refresh", json={"refresh_token": payload["refresh_token"]})
    assert old.status_code == 401
    # New password works.
    login = client.post(
        "/auth/login", json={"email": "user@moodly.test", "password": "brandNew99"}
    )
    assert login.status_code == 200


def test_reset_token_single_use(client: TestClient) -> None:
    register(client)
    forgot = client.post("/auth/forgot-password", json={"email": "user@moodly.test"})
    token = forgot.json()["reset_token"]
    assert client.post(
        "/auth/reset-password", json={"token": token, "password": "brandNew99"}
    ).status_code == 204
    again = client.post(
        "/auth/reset-password", json={"token": token, "password": "another99"}
    )
    assert again.status_code == 400


# --- account deletion ---------------------------------------------------------


def test_account_deletion_removes_private_data(client: TestClient) -> None:
    from sqlalchemy import select

    from app.db.base import JournalEntryRecord, MoodEntryRecord, User
    from app.db.session import SessionFactory

    payload = register(client)
    headers = auth_headers(payload)
    client.patch("/me", json={"cloud_sync_consent": True, "journal_upload_consent": True}, headers=headers)
    client.post(
        "/sync/push",
        headers=headers,
        json={
            "moods": [
                {
                    "client_id": "cli-del-0001",
                    "date": "2026-10-28",
                    "mood": "good",
                    "emotions": ["calm"],
                    "energy": 4,
                    "updated_at": "2026-10-28T20:00:00Z",
                }
            ],
            "journals": [
                {
                    "client_id": "cli-del-0002",
                    "date": "2026-10-28",
                    "body": "private thoughts",
                    "updated_at": "2026-10-28T20:00:00Z",
                }
            ],
            "journal_upload_consent": True,
        },
    )
    response = client.delete("/me", headers=headers)
    assert response.status_code == 204

    db = SessionFactory()
    try:
        assert db.scalar(select(User)) is None
        assert db.scalars(select(MoodEntryRecord)).all() == []
        assert db.scalars(select(JournalEntryRecord)).all() == []
    finally:
        db.close()
    # Old token no longer resolves an account.
    assert client.get("/me", headers=headers).status_code == 401
