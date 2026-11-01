# Moodly — Your Daily Mood

A calm, premium, **local-first** Flutter app for tracking your daily mood and
reflecting on patterns over time. Moodly records one mood check-in per day,
keeps a standalone journal, generates explainable insights and reports, and
now offers **optional** accounts, cloud sync and AI reflections through a
FastAPI backend.

Everything from Phases 1 and 2 — check-ins, calendar, journal, charts,
rule-based insights, reflections, exports and the Signature Lavender design —
still works **fully offline and without an account**. The backend is an
enhancement, not a dependency.

> **Verified state on this machine (2026-11-01):**
>
> - Flutter: `flutter analyze` clean, **168/168 tests passing**.
> - Backend: **55/55 pytest tests passing**; live server checked at
>   `/docs`, `/health` and `/ai/status`.
> - Database: the backend runs on **SQLite** by default. PostgreSQL is
>   supported by configuration (driver installed, migration prepared) but is
>   **not installed or activated** on this machine.
> - AI: **no provider key is configured**. `/ai/status` honestly returns
>   `ai_enabled=false`, `provider=none`, `mode=local_rules`, and both AI
>   endpoints fall back to local rule-based results. No claim of working AI is
>   made when it is not configured.
> - Security: no end-to-end encryption is claimed or implemented. Local SQLite
>   is not encrypted at rest; server data is protected by account
>   authentication and is HTTPS-ready (TLS is a deployment concern).

---

## Table of contents

- [Phase 3 features](#phase-3-features)
- [What works when](#what-works-when)
- [Phase 1 & 2 highlights](#phase-1--2-highlights)
- [Design system](#design-system)
- [Architecture](#architecture)
- [Tech stack](#tech-stack)
- [Prerequisites](#prerequisites)
- [Flutter setup](#flutter-setup)
- [Backend setup](#backend-setup)
- [PostgreSQL (ready, not activated)](#postgresql-ready-not-activated)
- [AI provider configuration](#ai-provider-configuration)
- [Authentication & sessions](#authentication--sessions)
- [Cloud sync & conflicts](#cloud-sync--conflicts)
- [Privacy model](#privacy-model)
- [API reference](#api-reference)
- [Screenshots](#screenshots)
- [Testing](#testing)
- [Project structure](#project-structure)
- [Database schema (v3)](#database-schema-v3)
- [JSON export](#json-export)
- [Known limitations](#known-limitations)
- [Phase 4 roadmap](#phase-4-roadmap)
- [License](#license)

---

## Phase 3 features

### Optional accounts

- Register, sign in, sign out, restore a session, update display name, change
  password via the reset flow, and **permanently delete the account**.
- **Argon2id** password hashing; passwords are never stored or logged.
- Access token (JWT, 30 min) + **rotating refresh token** (30 days, stored as a
  SHA-256 hash). Reusing an already-rotated refresh token revokes the whole
  token family.
- Tokens live in `flutter_secure_storage` on the device. Being signed out (or
  never signing up) is a first-class mode, not an error state.

### AI reflections (provider-independent)

- A clean `AiService` abstraction: `LocalAiService` (Phase 2 rules),
  `RemoteAiService` (backend) and `RoutingAiService`, which chooses the best
  available source and reports which one was genuinely used.
- Backend: `AiProvider` interface + `OpenAiProvider` (OpenAI-compatible chat
  completions via `httpx`, with timeouts and retries), strict prompts, a
  defensive parser, and a safety layer.
- Structured reflections include a summary, **explicit emotions** (words the
  user actually wrote) kept separate from **inferred emotions**, themes,
  positive observations, challenges, and exactly three reflection questions.
- The UI labels every reflection as **AI** or **Local** and shows an honest
  disclaimer. If a remote call fails, the local reflection is returned and the
  screen explains why the fallback happened.
- Journal text is sent **only** after both: the user is signed in with the
  AI-processing consent on, and the user explicitly taps “Reflect” on a single
  entry. No background AI processing.

### Reports

- **Weekly and monthly reports** built from real local data (works offline).
- The narrative is written locally by explainable rules; when signed in with
  AI consent, the backend may generate the narrative from **aggregate
  statistics only** (never journal text). The source is always labelled.
- Comparisons with the previous period appear only when both periods have
  enough data — no invented numbers.
- Reports are stored locally in `generated_reports`, viewable/deletable
  offline, and cleared by “Clear all data”.
- Every report states what it is not: a health assessment, diagnosis or
  treatment.

### Optional cloud sync (local-first)

- Off by default, opt-in per account, and **manual** (“Sync now”) rather than a
  hidden background process.
- Moods sync with the cloud-sync consent. Journal entries require **two
  independent consents**: the local journal-upload toggle *and* the server-side
  account flag. Without both, journal rows are rejected and reported.
- Stable `client_id` values (UUIDv4) make uploads idempotent; a pull cursor
  makes downloads incremental; tombstones propagate deletions.
- **Conflicts are never silently overwritten.** The row with the newer
  `updated_at` wins; the losing copy is surfaced to the user and remains
  pending for the next run.
- Network failures leave local data untouched; the last error and retry state
  are visible on the sync screen.

### Privacy controls

- A dedicated **Privacy & data** screen: connection/AI status, three explicit
  consent switches, a “what is stored where” map, and the AI disclaimer.
- Consent switches are disabled until signed in, so they cannot be toggled
  accidentally in local-only mode.
- Account deletion removes the account, tokens, sync rows and consents on the
  server, and clears local consent flags.
- Safe logging: journal text is never written to server logs; validation
  errors return field names, not raw values; 5xx bodies are not echoed to the
  app.
- No false claims: no end-to-end encryption, no model training on user data, no
  diagnostics disguised as AI.

---

## What works when

| Capability | Offline, no account | Signed in, no AI key | Signed in + AI key |
| --- | --- | --- | --- |
| Check-ins, calendar, journal, charts | ✅ | ✅ | ✅ |
| Local rule-based insights & reflections | ✅ | ✅ | ✅ |
| Weekly/monthly local reports | ✅ | ✅ | ✅ |
| Account & session management | — | ✅ | ✅ |
| Cloud sync (moods / journals) | — | ✅ | ✅ |
| AI reflections | Local rules | Local rules (labelled) | Remote AI (labelled) |
| AI report narrative | Local rules | Local rules (labelled) | Remote AI (labelled) |

“AI key” refers to a key configured **only in the backend environment**. The
Flutter app never contains or receives provider keys.

---

## Phase 1 & 2 highlights

Phases 1 and 2 remain intact:

- **Home dashboard** — greeting, today’s mood, check-in action, weekly summary,
  streak, recent history and quick navigation.
- **Mood check-in** — five moods, ten emotion tags, energy 1–5, optional note,
  edit-instead-of-duplicate for the same local day, discard confirmation.
- **Calendar** — month view with mood indicators, day details, edit/check-in
  guards for future days.
- **Journal** — multiple entries per day, create/view/edit/delete,
  case-insensitive search and polished empty states.
- **Insights** — mood distribution, averages, 7-day trend, 14-day line chart,
  emotion frequencies, weekly/monthly/all-time filters, no invented data.
- **Phase 2 intelligence** — explainable mood analytics, pattern detection,
  insight cards, and local rule-based journal reflections with themes and
  questions.
- **Settings** — theme modes, JSON export, clear-all-data, privacy notes and
  app information.
- **Design** — the Signature Lavender palette, rounded cards, lavenders used
  sparingly, mint accents, dark mode, vector logo and polished states.

---

## Design system

Moodly uses a consistent **“Signature Lavender”** design language across all
screens. The design system is centralized in `lib/core/theme/`, so no widget
hardcodes brand colors.

### Color palette

| Role | Light | Dark |
| --- | --- | --- |
| Primary purple | `#7655C9` | `#B49AF5` |
| Secondary purple | `#A58AE8` | `#D2C4FA` |
| Light lavender | `#EEE8FF` | — |
| Mint accent | `#B9E8D2` | `#9DE2C3` |
| Main background | `#F8F6FF` | `#171321` |
| Card background | `#FFFFFF` | `#211C30` |
| Primary text | `#33264D` | `#F7F3FF` |
| Secondary text | `#82758F` | `#B9AEC9` |
| Borders | `#EAE5F3` | `#322A4B` |

Mood colors use gentle, brand-aligned variations (mint green, periwinkle,
amber, warm orange, rose) so each mood is distinguishable without relying on
color alone — every mood also has a distinct icon and label.

### Visual principles

- Rounded cards with a consistent 20 px radius, thin borders and subtle
  shadows.
- Purple for primary actions, selected navigation and important highlights;
  mint for secondary highlights and positive indicators.
- Lavender backgrounds used sparingly for grouped sections and mood cards.
- Clear typographic hierarchy; Roboto family.
- Polished empty, loading and error states with clear actions and retry
  support.
- Five bottom-navigation destinations: Home, Calendar, Journal, Insights,
  Settings.
- A local vector logo (no network dependency) on splash, home and settings.
- Responsive layouts for small and large phones.
- Light, dark and system theme modes persisted via `shared_preferences`.

---

## Architecture

### Flutter app

```
lib/
├── core/
│   ├── database/        SQLite schema v3 + migrations
│   ├── network/         ApiClient, TokenStore
│   ├── theme/           Signature Lavender palette + Material 3 themes
│   └── utils/           local-date keys, formatters
├── models/              Mood, Emotion, MoodEntry, JournalEntry, reflections, reports
├── repositories/        SQLite access (mood, journal, settings, reports)
├── services/            analytics, patterns, reflections, auth, sync, reports, AI routing
├── widgets/             reusable UI (cards, chips, selectors, states, logo)
└── features/            splash, shell, home, check_in, calendar, journal,
                         insights, ai_insights, settings, account, sync,
                         reports, privacy
```

- `AppServices` in `app.dart` wires the dependency graph once and exposes it
  through an `InheritedWidget`. Widget tests can use the same `MoodlyApp` with
  an in-memory database and mock preferences.
- Local repositories remain the source of truth. Services read and write local
  SQLite; the network is only used by the optional auth/sync/AI paths.
- `RoutingAiService` implements the Phase 2 `AiService` interface, so the
  journal screen does not care whether a reflection is local or remote.

### Backend

```
backend/app/
├── main.py              FastAPI factory, CORS, safe error handlers, routers
├── core/                typed settings, security (Argon2/JWT), deps,
│                        in-process rate limiting, safe logging
├── db/                  SQLAlchemy base/session
├── models/              users, refresh/reset tokens, synced rows
├── schemas/             Pydantic request/response contracts
├── services/
│   ├── auth_service.py  register/login/rotation/reset/delete
│   ├── sync_service.py  push/pull, consent gates, conflict resolution
│   └── ai/              provider, OpenAI adapter, prompts, parser, safety,
│                        local rules and the orchestration service
├── routers/             health, auth, account, sync, ai
├── alembic/             migration 0001 (PostgreSQL-ready schema)
└── tests/               auth, sync, AI, rate limiting (55 tests)
```

### AI reflection flow

```
Journal screen
  └─ user taps “Reflect” on ONE entry
       └─ RoutingAiService.isAvailable?
            = signed in && AI consent && backend reachable
                 ├─ no  → LocalAiService (Phase 2 rules) → label “Local”
                 └─ yes → POST /ai/reflection (Bearer token)
                            ├─ consent_given=false → 400
                            ├─ no provider key   → local_rules
                            └─ provider key
                                 ├─ success → AI result (explicit/inferred emotions)
                                 └─ timeout/error → local_rules fallback
```

The backend requires `consent_given=true` on the request, and the client only
sets it after the signed-in user has enabled AI processing and tapped Reflect.
Insight/report endpoints accept **aggregate statistics only** by schema.

### Sync flow

1. With consent and a session, “Sync now” pushes locally pending rows
   (`needsSync`) keyed by `client_id`, plus tombstones for local deletions.
2. The server upserts idempotently. Journal rows are rejected unless the
   request **and** the account carry journal-upload consent.
3. The server returns conflicts with its own copy; the app applies a server copy
   only when it is newer, otherwise keeps the local copy pending.
4. The app pulls rows updated after its stored cursor and applies them through
   the same conflict rule.
5. Success updates the cursor and last-sync time; failure leaves local data and
   the cursor untouched, with a visible error and retry.

---

## Tech stack

### Flutter app

| Concern | Choice |
| --- | --- |
| Framework | Flutter (stable) + Dart |
| UI | Material 3 |
| Local database | `sqflite` + `path` (SQLite, schema v3) |
| Preferences | `shared_preferences` |
| Secure tokens | `flutter_secure_storage` |
| HTTP | `http` |
| Calendar | `table_calendar` |
| Charts | `fl_chart` |
| Dates | `intl` |
| Export / share | `path_provider` + `share_plus` |
| Tests (desktop DB) | `sqflite_common_ffi` (dev dependency) |

### Backend

| Concern | Choice |
| --- | --- |
| Framework | FastAPI + Uvicorn |
| Database | SQLAlchemy 2 + Alembic (SQLite now, PostgreSQL-ready) |
| Validation | Pydantic v2 + pydantic-settings |
| Passwords | Argon2id (`argon2-cffi`) |
| Tokens | PyJWT (access) + hashed rotating refresh tokens |
| AI HTTP client | `httpx` |
| PostgreSQL driver | `psycopg2-binary` |
| Tests | pytest + FastAPI TestClient |

Versions are pinned in `pubspec.yaml`, `backend/requirements.txt` and
`backend/requirements-dev.txt`.

---

## Prerequisites

- **Flutter SDK** stable — verified with **Flutter 3.47.8 / Dart 3.13.7**
  (recent stable ≥ 3.44 should work).
- **Android Studio** or Android SDK + command-line tools for the emulator.
- **Python 3.11+** for the backend — verified with **Python 3.13.4**.
- **PostgreSQL** only if you want to activate the production database target
  (not required for local development; not installed on this machine).

```powershell
flutter doctor
flutter --version
python --version
```

---

## Flutter setup

Run from the project root (the directory containing `pubspec.yaml`):

```powershell
flutter pub get
dart format .
flutter analyze
flutter test
```

Run on an Android emulator (recommended) or Windows desktop:

```powershell
flutter run
flutter run -d windows
```

The app’s default backend URL is `http://10.0.2.2:8000` (the Android
emulator’s alias for the host machine). It can be changed in
**Settings → Cloud sync → Server URL**; on a physical device use the host’s LAN
address.

> **Windows/Gradle note:** if the Android build fails with Kotlin “Could not
> close incremental caches”, add `kotlin.incremental=false` to
> `android/gradle.properties`. The Dart code is unaffected.

---

## Backend setup

All commands are PowerShell, from the `backend` folder:

```powershell
cd backend

# 1. Create an isolated environment
python -m venv .venv
.venv\Scripts\python.exe -m pip install --upgrade pip

# 2. Install runtime + test dependencies
.venv\Scripts\python.exe -m pip install -r requirements-dev.txt

# 3. Create local configuration (never commit .env)
Copy-Item .env.example .env
# Edit .env and set a real SECRET_KEY:
#   python -c "import secrets; print(secrets.token_hex(32))"

# 4. Create/upgrade the database schema
.venv\Scripts\python.exe -m alembic upgrade head

# 5. Start the API
.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

- Swagger UI: <http://127.0.0.1:8000/docs>
- ReDoc: <http://127.0.0.1:8000/redoc>
- OpenAPI JSON: <http://127.0.0.1:8000/openapi.json>
- Health: <http://127.0.0.1:8000/health>
- AI mode: <http://127.0.0.1:8000/ai/status>

### Environment variables

Copy `backend/.env.example` to `backend/.env`; the example contains **only
placeholders**. The variables below are read by `app/core/config.py`.

| Variable | Default | Purpose |
| --- | --- | --- |
| `DATABASE_URL` | `sqlite:///./moodly_backend.db` | SQLAlchemy URL; see PostgreSQL below |
| `SECRET_KEY` | — | JWT signing secret (required outside dev) |
| `ACCESS_TOKEN_MINUTES` | `30` | Access-token lifetime |
| `REFRESH_TOKEN_DAYS` | `30` | Refresh-token lifetime |
| `MOODLY_DEV_MODE` | `0` | Enables a random dev key and reset-token responses |
| `CORS_ORIGINS` | `http://localhost:5173` | Comma-separated allowed origins |
| `RATE_LIMIT_ENABLED` | `1` | Enable in-process rate limiting |
| `AI_REQUESTS_PER_MINUTE` | `15` | Per-user AI request budget |
| `AUTH_REQUESTS_PER_MINUTE` | `20` | Per-IP auth request budget |
| `OPENAI_API_KEY` | empty | Provider key; empty = local-rules fallback |
| `OPENAI_MODEL` | `gpt-4o-mini` | Model name |
| `OPENAI_BASE_URL` | `https://api.openai.com/v1` | OpenAI-compatible endpoint |
| `OPENAI_TIMEOUT_SECONDS` | `30` | Provider request timeout |
| `LOG_LEVEL` | `INFO` | Log verbosity |

Startup guard: outside dev/test mode the backend **refuses to start** without
a real `SECRET_KEY` (values starting with `CHANGE_ME` count as placeholders).

> **Development caveat:** with `MOODLY_DEV_MODE=1` and no `SECRET_KEY`, the
> server generates a temporary random key on every start, so existing tokens
> become invalid after a restart. Set a persistent key in `.env` for a stable
> dev session.

> **Password reset delivery:** this build has no SMTP provider. In dev mode the
> reset token is returned in the API response so the flow is testable; in
> production the token would be delivered by an email provider (not included
> yet). The API never reveals whether an email exists.

---

## PostgreSQL (ready, not activated)

PostgreSQL is the documented production target but is **not installed on this
machine**, so every check above ran against SQLite. The codebase is ready:

- `psycopg2-binary` is installed via `requirements.txt`.
- All models use portable SQLAlchemy types; the Alembic migration targets the
  configured database.
- Switching is a single variable change:

```dotenv
# backend/.env
DATABASE_URL=postgresql+psycopg2://moodly:CHANGE_ME@localhost:5432/moodly
```

```powershell
.venv\Scripts\python.exe -m alembic upgrade head
.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Create the `moodly` database/user in PostgreSQL first and keep the password in
`.env` only. No application code or schema changes are required. This path was
not executed here because PostgreSQL is absent.

---

## AI provider configuration

Configure the provider **only on the backend**:

```dotenv
# backend/.env
OPENAI_API_KEY=sk-your-real-key-here
OPENAI_MODEL=gpt-4o-mini
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_TIMEOUT_SECONDS=30
```

Then restart Uvicorn and check `/ai/status`:

```json
{ "ai_enabled": true, "provider": "openai", "mode": "remote_ai" }
```

Rules the implementation enforces:

- Keys are read from environment variables and are never returned by the API,
  logged, or shipped in the Flutter app.
- Without a key, `ai_enabled=false`; AI endpoints return
  `source: "local_rules"` and the UI labels them **Local**.
- With a key but a provider failure/timeout/rate limit, the endpoint falls back
  to local rules instead of failing the user’s flow.
- `/ai/reflection` accepts journal text only with `consent_given=true`; the
  journal is never logged.
- `/ai/insights` and `/ai/report-narrative` accept aggregates only — their
  schemas have no journal-text field.
- AI requests are rate limited per user (`AI_REQUESTS_PER_MINUTE`, default 15)
  and auth requests per IP (`AUTH_REQUESTS_PER_MINUTE`, default 20). The
  limiter is in-process (single instance); use a shared store for multi-instance
  deployments.
- The `AiProvider` interface (`backend/app/services/ai/provider.py`) isolates
  the vendor. `OpenAiProvider` is one implementation; adding another provider
  does not touch the routers, schemas or app.

**Honest scope note:** the Flutter **Insights** screen still uses the Phase 2
local analytics; the backend `/ai/insights` endpoint is implemented, tested and
available, but is not called by the current UI. AI is used by the app for
journal reflections and report narratives when configured.

---

## Authentication & sessions

1. `POST /auth/register` or `POST /auth/login` returns an access token and a
   refresh token. Passwords are hashed with Argon2id.
2. `ApiClient` attaches the access token to protected requests. On a `401`, it
   performs **one** refresh + retry via `AuthService`.
3. Refresh tokens rotate on every use. The server stores only SHA-256 hashes,
   grouped into families; reusing a rotated token revokes the family.
4. `POST /auth/logout` revokes the presented refresh token; the app always
   clears local tokens even if the server call fails.
5. `DELETE /me` permanently removes the account, tokens and synced rows, then
   clears local tokens and consent flags.
6. Reset flow: `POST /auth/forgot-password` → `POST /auth/reset-password`
   (single-use, hashed, short-lived token; signs out all sessions).

Local-only mode requires none of this. The app restores a stored session
optimistically when offline and validates lazily; platform-channel failures
degrade to local-only instead of crashing.

---

## Cloud sync & conflicts

- **Opt-in:** off by default; requires a signed-in account and the cloud-sync
  consent.
- **Local-first:** local SQLite is always authoritative for the UI; sync never
  blocks normal use.
- **Idempotent uploads:** stable UUID `client_id` per row; the server upserts
  keyed by `(user_id, client_id)`.
- **Journal double gate:** local journal-upload consent **and** the server-side
  account flag. The request also carries the flag; missing consent yields
  `journal_rejected_missing_consent` counts, not an error page.
- **Incremental pulls:** the server returns rows with `server_updated_at`
  greater than the client’s cursor; the cursor advances only on success.
- **Conflict rule:** last-write-wins by the row’s own client `updated_at`.
  `server_updated_at` is only the pull cursor. The server returns its copy for
  conflicts; the app applies it only when it is newer, otherwise keeps the
  local copy pending. Counts of resolved/kept-local conflicts are shown.
- **Deletions:** locally deleted rows with a `client_id` produce tombstones,
  including rows that were never uploaded (resurrection guard).
- **Failures:** local data and the cursor are untouched; the screen shows the
  error and “Sync now” can retry.

Sync is intentionally **manual** in this phase (no background schedule). The
sync screen shows pending counts, last sync time, the server URL, and the
conflict explanation.

---

## Privacy model

| Data | Where it lives | Leaves the device? |
| --- | --- | --- |
| Mood check-ins | Local SQLite | Only with cloud-sync consent |
| Journal entries | Local SQLite | Only with cloud sync **and** journal-upload consent |
| Reflections & reports | Local SQLite | no (reflections themselves are not synced) |
| AI reflection input | Backend → provider | One entry, only after AI consent + per-entry Reflect |
| AI insight/report input | Backend → provider | Aggregate statistics only |
| Account credentials | Backend | Argon2id hash; never plaintext |
| Tokens | Device secure storage + hashed on server | Access/refresh JWTs |

- Every consent switch starts **OFF** and is disabled without an account.
- Turning consents off stops the corresponding future transfers; server-side
  journal consent is updated when signed in.
- “Clear all data” removes local moods, journals, reflections and generated
  reports after confirmation and resets sync metadata.
- Server logs never include journal bodies. Generic 500 responses do not echo
  internals to the app.
- **No end-to-end encryption is claimed.** Local SQLite is plaintext in the
  app’s private storage. Server transport should be TLS in a real deployment
  (the code is HTTPS-ready; local development uses plain HTTP on loopback).
- User data is **not used to train models**; the app and prompts say so.
- AI output can be inaccurate and is presented as a reflection aid, never a
  medical or mental-health evaluation.

---

## API reference

Base URL: `http://127.0.0.1:8000`. Interactive docs: `/docs`.
Protected routes expect `Authorization: Bearer <access token>`.

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| `GET` | `/health` | no | Service liveness |
| `GET` | `/ai/status` | no | Honest AI mode (`local_rules` vs `remote_ai`) |
| `POST` | `/auth/register` | no | Create account + token pair |
| `POST` | `/auth/login` | no | Sign in |
| `POST` | `/auth/refresh` | no | Rotate refresh token |
| `POST` | `/auth/logout` | yes | Revoke refresh token |
| `POST` | `/auth/forgot-password` | no | Request reset token (dev returns it) |
| `POST` | `/auth/reset-password` | no | Set new password |
| `GET` | `/me` | yes | Profile + consents |
| `PATCH` | `/me` | yes | Update display name / consents |
| `DELETE` | `/me` | yes | Delete account and private data |
| `POST` | `/sync/push` | yes | Upload pending moods/tombstones/journals |
| `POST` | `/sync/pull` | yes | Download changes after a cursor |
| `POST` | `/ai/reflection` | yes | One-entry reflection (`consent_given=true`) |
| `POST` | `/ai/insights` | yes | 2–6 cards from aggregates only |
| `POST` | `/ai/report-narrative` | yes | Report narrative from aggregates only |

All endpoints return JSON except `204` logout/account-deletion responses.
Validation errors use `{"detail": "Validation failed", "errors": [{field,
message}]}` and never echo input values.

---

## Screenshots

> Placeholder images — drop real captures in `docs/screenshots/` and reference
> them here once available.

| Home | Check-in | Calendar |
| --- | --- | --- |
| ![home](docs/screenshots/home.png) | ![check-in](docs/screenshots/check_in.png) | ![calendar](docs/screenshots/calendar.png) |

| Journal | Insights | Settings |
| --- | --- | --- |
| ![journal](docs/screenshots/journal.png) | ![insights](docs/screenshots/insights.png) | ![settings](docs/screenshots/settings.png) |

---

## Testing

### Flutter

```powershell
flutter pub get
dart format .
flutter analyze
flutter test
```

**Verified result:** `flutter analyze` reports no issues; `flutter test` reports
**168 tests passed**.

Coverage highlights:

- Models, repositories, one-check-in-per-day, journal CRUD/search, analytics,
  patterns, insights, reflections, export and migrations (Phases 1–2).
- **Phase 3** (`test/phase3/`):
  - `api_client_test.dart` — auth header, 401 refresh/retry, error mapping,
    no request-body leakage.
  - `auth_service_test.dart` — register/login/restore/logout/deletion, consent
    mirroring, reset flow.
  - `ai_routing_test.dart` — remote success, offline/500/429 fallbacks and
    fallback reasons.
  - `sync_service_test.dart` — consent gates, conflict handling, failure
    safety, pending counts.
  - `report_service_test.dart` — weekly/monthly windows, storage, local vs AI
    narrative, honest comparisons.
  - `database_v3_migration_test.dart` — v2 → v3 upgrade preserving rows,
    backfilling client ids, adding new tables/columns, idempotency.
  - `phase3_screens_test.dart` — settings entries, account form, consent
    gating, sync screen, offline report generation.
- Existing end-to-end widget flows are unchanged and still pass.

Run a subset:

```powershell
flutter test test/phase3
flutter test --plain-name "privacy screen"
```

### Backend

```powershell
cd backend
.venv\Scripts\python.exe -m pytest tests -q
```

**Verified result:** **55 tests passed** (one upstream Starlette/anyio
deprecation warning).

Coverage: registration/login/rotation/reuse-revocation, logout, password reset,
profile/consent updates, account deletion and data isolation; sync push/pull,
idempotency, journal consent, conflicts/tombstones; AI fallback, consent
enforcement, aggregate-only schemas, parser/safety behavior; per-user/per-IP
rate limits.

### Live smoke test performed

While Uvicorn ran on `127.0.0.1:8000`:

- `/health` → `{"status":"ok"}`
- `/ai/status` → `ai_enabled=false`, `provider=none`, `mode=local_rules`
- `/docs` → HTTP 200 (Swagger UI)
- register → `/me` → `/ai/reflection` (consent) → `source=local_rules`, 3
  questions, explicit emotions detected → `/ai/insights` →
  `source=local_rules` → `DELETE /me` → account removed
- Throwaway smoke accounts were cleaned up afterward.

---

## Project structure

```
lib/
├── main.dart                     # Entry point: init date symbols, load prefs, run app
├── app.dart                      # MoodlyApp root + AppServices DI
├── core/
│   ├── database/app_database.dart    # SQLite v3 schema/migrations
│   ├── network/
│   │   ├── api_client.dart           # HTTP, bearer tokens, 401 refresh/retry
│   │   └── token_store.dart          # flutter_secure_storage wrapper
│   ├── theme/                        # Signature Lavender palette + themes
│   └── utils/                        # dates, formatters
├── models/                       # mood, emotion, entries, reflection, report, client ids
├── repositories/                 # mood, journal, settings, reports (SQLite)
├── services/                     # analytics, patterns, reflections, auth, sync,
│                                 # reports, export, local/remote/routing AI
├── widgets/                      # cards, chips, selectors, states, logo
└── features/
    ├── splash/ shell/ home/ check_in/ calendar/
    ├── journal/                  # list/detail/editor/reflection
    ├── insights/ ai_insights/    # Phase 1 charts + Phase 2 insight cards
    ├── settings/
    ├── account/                  # auth forms, profile, deletion
    ├── sync/                     # consent, server URL, conflicts
    ├── reports/                  # weekly/monthly list + detail
    └── privacy/                  # consents + transparency
test/
├── helpers/test_harness.dart     # FFI/in-memory/temp-file DB factories
├── ...                           # Phase 1–2 unit/widget tests
└── phase3/                       # seven Phase 3 test files

backend/
├── app/                          # FastAPI application (see Architecture)
├── alembic/versions/0001_initial.py
├── tests/                        # pytest suite
├── requirements.txt
├── requirements-dev.txt
├── .env.example                  # placeholders only
├── alembic.ini
└── README is this file
```

---

## Database schema (v3)

Local SQLite is created at the platform databases path as `moodly.db` and is
migrated through versioned `onUpgrade` steps. Migration from v2 preserves all
existing rows.

### `mood_entries`

| Column | Type | Notes |
| --- | --- | --- |
| `id` | INTEGER | Primary key |
| `date` | TEXT | `yyyy-MM-dd` local day, `UNIQUE` → one/day |
| `mood` | TEXT | Stable mood name |
| `emotions` | TEXT | Comma-separated emotion names |
| `energy` | INTEGER | 1–5 |
| `note` | TEXT | Optional |
| `created_at` / `updated_at` | INTEGER | UTC epoch milliseconds |
| `client_id` | TEXT | Stable UUID for sync (backfilled in v3) |
| `synced_at` | INTEGER | Last successful sync (nullable) |

### `journal_entries`

Same core fields as Phase 1, plus indexed `date`, `client_id` and `synced_at`.

### `journal_reflections`

Phase 2 fields plus Phase 3 AI fields:

| Column | Notes |
| --- | --- |
| `positive_observations` | Comma-separated observations |
| `challenges` | Comma-separated challenges |
| `explicit_emotions` | Emotions the user actually expressed |
| `inferred_emotions` | Emotions inferred by the model/rules |
| `provider` | `local_rules` or the remote provider label |

Existing rows default to `local_rules` during migration.

### `generated_reports`

| Column | Notes |
| --- | --- |
| `kind` | `weekly` or `monthly` |
| `period_start` / `period_end` | Local dates |
| `period_label` | Display label |
| `data` | JSON statistics payload |
| `narrative_source` | `local_rules` or `ai:<provider>` |
| `created_at` | UTC epoch milliseconds |
| unique | `(kind, period_start)` |

### `sync_tombstones`

| Column | Notes |
| --- | --- |
| `kind` | `mood` or `journal` |
| `client_id` | Row identifier |
| `deleted_at` | UTC epoch milliseconds |
| unique | `(kind, client_id)` |

**Local dates:** entries are keyed by the device’s local calendar day so
“today” matches what the user sees. Timestamps are UTC; comparisons use
normalized date-only keys to avoid timezone drift.

> ⚠️ **Local storage is NOT encrypted by default.** SQLite files are plain
> files in the app’s private storage. Anyone with root/device access or a
> leaked backup could read them. Encryption at rest remains future work.

### Backend tables

`users`, `refresh_tokens`, `password_reset_tokens`, `mood_entries`,
`journal_entries` (server-side copies, created by
`backend/alembic/versions/0001_initial.py`). Refresh/reset tokens are stored
only as SHA-256 hashes; deletions on the server are soft (`is_deleted`
tombstones) so other devices can learn about them.

---

## JSON export

Settings → **Export all data (JSON)** builds a UTF-8 document and hands it to
the OS share sheet after writing it to a temp file. It includes mood and
journal entries; generated reports/reflections are not part of the export yet.

```jsonc
{
  "app": "Moodly",
  "tagline": "Your Daily Mood",
  "schemaVersion": 1,
  "exportedAt": "2026-11-01T16:32:00.000",
  "exportedAtLocal": "2026-11-01 16:32:00",
  "counts": { "moodEntries": 42, "journalEntries": 7 },
  "moodEntries": [
    {
      "id": 1,
      "date": "2026-11-01",
      "mood": "great",
      "moodLabel": "Great",
      "emotions": ["calm", "grateful"],
      "energy": 4,
      "note": "A nice day.",
      "createdAt": "2026-11-01T16:30:00.000",
      "updatedAt": "2026-11-01T16:30:00.000"
    }
  ],
  "journalEntries": [
    {
      "id": 1,
      "date": "2026-11-01",
      "title": "Reflection",
      "body": "…",
      "createdAt": "2026-11-01T17:00:00.000",
      "updatedAt": "2026-11-01T17:00:00.000"
    }
  ]
}
```

**Clear all data** deletes moods, journals, reflections and generated reports
after an explicit confirmation, and resets local sync metadata.

---

## Known limitations

- **English-only UI.** `flutter_localizations` is not included; date symbols are
  initialized for English.
- **Local storage is not encrypted at rest** (see above).
- **No end-to-end encryption.** Server data is protected by account auth; TLS
  must be configured at deployment.
- **PostgreSQL is not active here.** SQLite is the verified runtime; the
  PostgreSQL path is configuration-ready but untested on this machine.
- **No AI provider key is configured here.** AI endpoints were verified in
  their honest `local_rules` mode; the remote provider adapter has unit tests
  and strict fallbacks, but no live vendor call was made.
- **No email delivery.** Password reset returns the token only in dev mode;
  production SMTP/email integration is future work.
- **Sync is manual.** No background scheduling, and conflicts keep the newer
  copy rather than offering a side-by-side merge UI.
- **Insights UI stays local.** The `/ai/insights` endpoint is available but the
  Insights screen still uses Phase 2 on-device analytics.
- **Reports/reflections are not exported** and are not synced between devices.
- **Rate limiting is in-process**, suitable for one backend instance only.
- **Local timezone:** the device’s local calendar defines “today”; changing the
  timezone changes day boundaries by design.

---

## Phase 4 roadmap

- **Encrypted local storage** — SQLCipher (or platform keystore-backed
  encryption) for data at rest; encrypt exports; revisit an honest E2E design
  before claiming E2E sync.
- **Production email** — SMTP/provider for password reset and account notices;
  remove dev-token responses outside development.
- **Sync improvements** — background/scheduled sync, side-by-side conflict
  resolution, syncing reflections/reports, and per-device status.
- **Wire AI insights** — use `/ai/insights` in the Insights screen with clear
  source labels, aggregate-only payloads and per-user consent.
- **Provider registry** — additional `AiProvider` implementations (local LLM,
  Anthropic-compatible, self-hosted) behind the existing interface.
- **Notifications & widgets** — daily reminders, home-screen widgets, watch
  companion.
- **Richer reports** — PDF/CSV export, custom date ranges, mood-by-weekday/hour
  and emotion correlations.
- **Localization & accessibility** — full translations, dynamic type audit,
  screen-reader refinements.
- **Operations** — PostgreSQL activation, shared rate-limit store (Redis),
  structured metrics, backup/restore runbooks.

---

## License

This project is provided as-is for the Moodly Phase 3 implementation.
