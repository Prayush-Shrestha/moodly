"""Cloud sync: dedup, conflict handling, consent gates, tombstones, isolation."""

from __future__ import annotations

from fastapi.testclient import TestClient

from tests.conftest import auth_headers, register


def _mood(client_id: str, date: str = "2026-10-28", mood: str = "good",
          updated_at: str = "2026-10-28T20:00:00Z", **extra) -> dict:
    row = {
        "client_id": client_id,
        "date": date,
        "mood": mood,
        "emotions": ["calm"],
        "energy": 4,
        "updated_at": updated_at,
    }
    row.update(extra)
    return row


def _journal(client_id: str, date: str = "2026-10-28", body: str = "entry",
             updated_at: str = "2026-10-28T20:00:00Z", **extra) -> dict:
    row = {
        "client_id": client_id,
        "date": date,
        "body": body,
        "updated_at": updated_at,
    }
    row.update(extra)
    return row


def _consent(client: TestClient, headers: dict[str, str]) -> None:
    response = client.patch(
        "/me", json={"journal_upload_consent": True, "cloud_sync_consent": True},
        headers=headers,
    )
    assert response.status_code == 200


def test_push_pull_roundtrip(client: TestClient) -> None:
    payload = register(client)
    headers = auth_headers(payload)
    response = client.post(
        "/sync/push",
        headers=headers,
        json={"moods": [_mood("cli-aaaa0001")], "journals": []},
    )
    assert response.status_code == 200
    assert response.json()["accepted_moods"] == ["cli-aaaa0001"]

    pull = client.post("/sync/pull", headers=headers, json={"cursor": None})
    assert pull.status_code == 200
    moods = pull.json()["moods"]
    assert len(moods) == 1
    assert moods[0]["client_id"] == "cli-aaaa0001"
    assert moods[0]["mood"] == "good"
    assert moods[0]["emotions"] == "calm"


def test_same_client_id_pushed_twice_does_not_duplicate(client: TestClient) -> None:
    payload = register(client)
    headers = auth_headers(payload)
    body = {"moods": [_mood("cli-aaaa0001")], "journals": []}
    client.post("/sync/push", headers=headers, json=body)
    # Same row, same/newer timestamp → upsert, not duplicate.
    client.post(
        "/sync/push",
        headers=headers,
        json={"moods": [_mood("cli-aaaa0001", mood="great",
                              updated_at="2026-10-29T08:00:00Z")], "journals": []},
    )
    pull = client.post("/sync/pull", headers=headers, json={"cursor": None})
    moods = pull.json()["moods"]
    assert len(moods) == 1
    assert moods[0]["mood"] == "great"


def test_newer_server_copy_wins_and_reports_conflict(client: TestClient) -> None:
    payload = register(client)
    headers = auth_headers(payload)
    client.post("/sync/push", headers=headers,
                json={"moods": [_mood("cli-aaaa0001", updated_at="2026-10-28T20:00:00Z")],
                      "journals": []})
    # Device B pushes an OLDER edit for the same client_id → conflict.
    response = client.post(
        "/sync/push",
        headers=headers,
        json={"moods": [_mood("cli-aaaa0001", mood="terrible",
                              updated_at="2026-10-27T08:00:00Z")], "journals": []},
    )
    data = response.json()
    assert data["accepted_moods"] == []
    assert len(data["mood_conflicts"]) == 1
    conflict = data["mood_conflicts"][0]
    assert conflict["client_id"] == "cli-aaaa0001"
    assert conflict["server_version"]["mood"] == "good"  # server version returned


def test_newer_client_edit_overwrites_server(client: TestClient) -> None:
    payload = register(client)
    headers = auth_headers(payload)
    client.post("/sync/push", headers=headers,
                json={"moods": [_mood("cli-aaaa0001", updated_at="2026-10-27T08:00:00Z")],
                      "journals": []})
    response = client.post(
        "/sync/push",
        headers=headers,
        json={"moods": [_mood("cli-aaaa0001", mood="great",
                              updated_at="2026-10-28T08:00:00Z")], "journals": []},
    )
    assert response.json()["accepted_moods"] == ["cli-aaaa0001"]
    pull = client.post("/sync/pull", headers=headers, json={"cursor": None})
    assert pull.json()["moods"][0]["mood"] == "great"


def test_invalid_emotion_rejected(client: TestClient) -> None:
    payload = register(client)
    headers = auth_headers(payload)
    response = client.post(
        "/sync/push",
        headers=headers,
        json={"moods": [_mood("cli-aaaa0001", emotions=["made-up"])], "journals": []},
    )
    assert response.status_code == 422


def test_journals_rejected_without_account_consent(client: TestClient) -> None:
    payload = register(client)
    headers = auth_headers(payload)
    response = client.post(
        "/sync/push",
        headers=headers,
        json={
            "moods": [],
            "journals": [_journal("cli-jjjj0001", body="secret")],
            "journal_upload_consent": True,  # request says yes, account says no
        },
    )
    data = response.json()
    assert data["accepted_journals"] == []
    assert data["journal_rejected_missing_consent"] == ["cli-jjjj0001"]
    pull = client.post("/sync/pull", headers=headers, json={"cursor": None})
    assert pull.json()["journals"] == []


def test_journals_rejected_without_request_consent(client: TestClient) -> None:
    payload = register(client)
    headers = auth_headers(payload)
    _consent(client, headers)
    response = client.post(
        "/sync/push",
        headers=headers,
        json={"moods": [],
              "journals": [_journal("cli-jjjj0001")],
              "journal_upload_consent": False},
    )
    assert response.json()["journal_rejected_missing_consent"] == ["cli-jjjj0001"]


def test_journals_accepted_with_double_consent(client: TestClient) -> None:
    payload = register(client)
    headers = auth_headers(payload)
    _consent(client, headers)
    response = client.post(
        "/sync/push",
        headers=headers,
        json={"moods": [],
              "journals": [_journal("cli-jjjj0001", body="my private words")],
              "journal_upload_consent": True},
    )
    assert response.json()["accepted_journals"] == ["cli-jjjj0001"]
    pull = client.post("/sync/pull", headers=headers, json={"cursor": None})
    journals = pull.json()["journals"]
    assert len(journals) == 1
    assert journals[0]["body"] == "my private words"


def test_delete_tombstone_propagates(client: TestClient) -> None:
    payload = register(client)
    headers = auth_headers(payload)
    client.post("/sync/push", headers=headers,
                json={"moods": [_mood("cli-aaaa0001")], "journals": []})
    # Local delete → push tombstone (is_deleted).
    client.post(
        "/sync/push",
        headers=headers,
        json={"moods": [_mood("cli-aaaa0001", is_deleted=True,
                              updated_at="2026-10-29T09:00:00Z")], "journals": []},
    )
    pull = client.post("/sync/pull", headers=headers, json={"cursor": None})
    moods = pull.json()["moods"]
    assert len(moods) == 1
    assert moods[0]["is_deleted"] is True


def test_cursor_limits_results_to_changes(client: TestClient) -> None:
    payload = register(client)
    headers = auth_headers(payload)
    client.post("/sync/push", headers=headers,
                json={"moods": [_mood("cli-aaaa0001")], "journals": []})
    first = client.post("/sync/pull", headers=headers, json={"cursor": None}).json()
    # Nothing changed since → empty result with fresh cursor.
    second = client.post(
        "/sync/pull", headers=headers, json={"cursor": first["cursor"]}
    ).json()
    assert second["moods"] == []
    # A new row shows up against the old cursor.
    client.post("/sync/push", headers=headers,
                json={"moods": [_mood("cli-aaaa0002", date="2026-10-29")], "journals": []})
    third = client.post(
        "/sync/pull", headers=headers, json={"cursor": first["cursor"]}
    ).json()
    assert [m["client_id"] for m in third["moods"]] == ["cli-aaaa0002"]


def test_users_only_see_their_own_rows(client: TestClient) -> None:
    user_a = register(client, email="a@moodly.test")
    user_b = register(client, email="b@moodly.test")
    headers_a, headers_b = auth_headers(user_a), auth_headers(user_b)
    client.post("/sync/push", headers=headers_a,
                json={"moods": [_mood("cli-aaaa0001")], "journals": []})
    client.post("/sync/push", headers=headers_b,
                json={"moods": [_mood("cli-bbbb0001", date="2026-10-27", mood="low")],
                      "journals": []})
    pull_a = client.post("/sync/pull", headers=headers_a, json={"cursor": None}).json()
    pull_b = client.post("/sync/pull", headers=headers_b, json={"cursor": None}).json()
    assert [m["client_id"] for m in pull_a["moods"]] == ["cli-aaaa0001"]
    assert [m["client_id"] for m in pull_b["moods"]] == ["cli-bbbb0001"]
    # Same client_id under two users stays distinct rows.
    assert pull_b["moods"][0]["mood"] == "low"


def test_access_token_from_deleted_account_rejected(client: TestClient) -> None:
    payload = register(client)
    headers = auth_headers(payload)
    client.delete("/me", headers=headers)
    response = client.post("/sync/pull", headers=headers, json={"cursor": None})
    assert response.status_code == 401
