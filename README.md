# Moodly — Your Daily Mood

A calm, premium, local-first Flutter app for tracking your daily mood and
reflecting on patterns over time. Moodly records one mood check-in per day,
keeps a standalone journal, and turns your saved entries into real insights —
all stored on-device, working fully offline.

> **Phase 1** is local-only: no backend, no accounts, no AI, no network needed.

---

## Table of contents

- [Phase 1 features](#phase-1-features)
- [Screenshots](#screenshots)
- [Tech stack](#tech-stack)
- [Prerequisites](#prerequisites)
- [Windows setup](#windows-setup)
- [Running on an Android emulator](#running-on-an-android-emulator)
- [Running tests](#running-tests)
- [Project structure](#project-structure)
- [Database & data model](#database--data-model)
- [JSON export](#json-export)
- [Known limitations](#known-limitations)
- [Phase 2 ideas](#phase-2-ideas)

---

## Phase 1 features

- **Home dashboard** — time-of-day greeting, today's date, today's mood (or a
  friendly empty state), a prominent **Check in** action, a weekly summary
  (check-ins, average mood, average energy, per-day mood dots), recent history,
  and quick navigation to the other tabs.
- **Mood check-in** — five moods (Great, Good, Okay, Low, Terrible) with
  distinctive accessible colors/icons; ten emotion tags (Calm, Happy, Excited,
  Grateful, Motivated, Tired, Stressed, Anxious, Sad, Angry); energy level 1–5;
  an optional note; save/edit/validation/cancel with a discard confirmation.
- **Calendar** — month view (table_calendar) with mood indicators on days that
  have an entry; selecting a day shows the saved entry and lets you edit it or
  check in for that day (future days are guarded).
- **Journal** — create, view, edit and delete standalone entries (multiple per
  day), with case-insensitive search across titles and bodies and useful empty
  states.
- **Insights** — real analytics computed from your saved entries: mood counts
  and distribution (fl_chart bar chart), average mood & energy, a recent
  7-days-vs-previous-7-days trend, a 14-day daily-average line chart, and most
  frequently selected emotions. Weekly / monthly / all-time filters. Shows a
  helpful empty state before any entries exist — **no data is ever invented**.
- **Settings** — light/dark/system theme, app information & privacy note,
  **export all data to JSON**, and **clear all data** behind an explicit
  confirmation dialog.
- **Splash/launch** — a short, branded launch screen (local vector logo, no
  network dependency) shown while the local database opens.

Data persists across app restarts. At most **one mood check-in per local
calendar day** — checking in again the same day opens the existing entry for
editing instead of creating a duplicate.

---

## Phase 2: AI-Powered Mood Intelligence

Phase 2 transforms Moodly from a simple tracker into an intelligent personal
mood-insights application. All new intelligence is **local and rule-based**:
nothing is invented, nothing is a medical diagnosis, and no journal or mood
data leaves the device.

### New Phase 2 features

- **AI Insights screen** — personalized insight cards computed from your real
  saved entries: mood distribution, average energy, emotion patterns, check-in
  consistency, streaks, and weekly/monthly summaries. Each insight shows the
  data it is based on and a qualitative confidence level.
- **Mood trends** — mood trend chart and energy trend chart (fl_chart) with
  tooltips, plus emotion frequency charts. Weekly / monthly / all-time filters.
- **Journal reflection** — from a journal entry detail, tap "Reflect on this
  entry" to get a local rule-based reflection: a summary, emotions detected in
  your words, themes, and suggested reflection questions. Reflections are
  optional, stored locally, and clearly labeled as rule-based (they may be
  inaccurate and are not medical advice).
- **Home enhancements** — current check-in streak, weekly mood overview, one
  surface insight, and quick access to AI Insights.
- **AI integration architecture** — an `AiService` abstraction with a
  `LocalAiService` (offline, rule-based) and a `RemoteAiService` stub for a
  future provider. No API keys are stored in source code, and no data is sent
  externally without explicit consent.

### Mood analysis methodology

All analysis uses simple, explainable statistics over your own SQLite data:

- **MoodAnalyticsService** — totals, dominant mood, average mood & energy,
  average energy by mood, mood / emotion distributions.
- **MoodPatternService** — rule-based patterns such as "Good or Great on X of
  the last 7 days," "energy higher on Motivated days," streaks, and missing
  days.
- **InsightGenerationService** — turns patterns into displayable insight cards;
  empty or sparse datasets produce a helpful message instead of invented
  conclusions.

Rule-based insights are **not machine learning** and are never presented as
clinical conclusions. Moodly does not diagnose depression, anxiety, or any
medical condition.

### Privacy and data handling

- Local SQLite storage is **not encrypted by default** (see the Phase 1 storage
  note). Generated reflections are stored in a new `journal_reflections` table
  linked to journal entries; deleting a journal entry cascades and removes its
  reflection.
- "Clear all data" also removes generated reflections and insights data.
- No API keys in source code. No automatic upload of journal entries.
- Reflections are generated locally and labeled rule-based. A future remote AI
  provider would require explicit user consent before any data leaves the
  device.

---

## Screenshots

> Placeholder images — drop real captures in `docs/screenshots/` and reference
> them here once available.

| Home | Check-in | Calendar |
| ---- | -------- | -------- |
| ![home](docs/screenshots/home.png) | ![check-in](docs/screenshots/check_in.png) | ![calendar](docs/screenshots/calendar.png) |

| Journal | Insights | Settings |
| ------- | -------- | -------- |
| ![journal](docs/screenshots/journal.png) | ![insights](docs/screenshots/insights.png) | ![settings](docs/screenshots/settings.png) |

---

## Tech stack

| Concern            | Choice                                    |
| ------------------ | ----------------------------------------- |
| Framework          | Flutter (stable) + Dart                   |
| UI                 | Material 3                                |
| Local database     | `sqflite` + `path` (SQLite)               |
| Preferences        | `shared_preferences`                      |
| Calendar           | `table_calendar`                          |
| Charts             | `fl_chart`                                |
| Dates              | `intl`                                    |
| Export / share     | `path_provider` + `share_plus`            |
| Tests (desktop DB) | `sqflite_common_ffi` (dev dependency)     |

Versions are pinned to stable, mutually compatible releases (see
`pubspec.yaml`).

---

## Prerequisites

- **Flutter SDK** (stable channel) — this project was built and verified with
  **Flutter 3.47.8 / Dart 3.13.7**. Any recent stable Flutter ≥ 3.44 should
  work.
- **Android Studio** (or Android SDK + command-line tools) for the emulator and
  native build toolchain.
- **A device or emulator**: a connected Android device with developer options,
  or an Android emulator created in Android Studio's Device Manager.

Verify your toolchain:

```powershell
flutter doctor
flutter --version
```

---

## Windows setup

All commands below are PowerShell, run from the project folder
(the directory that contains `pubspec.yaml`).

```powershell
# 1. Fetch dependencies
flutter pub get

# 2. Static analysis (must be clean)
flutter analyze

# 3. Format the code
dart format .

# 4. Run the tests
flutter test
```

If `flutter` is not on your `PATH`, run it from the full path to your Flutter
SDK's `bin\flutter.bat`, or add the SDK `bin` directory to your `PATH`.

> The Android build uses the Gradle wrapper (`android\gradlew`). The first build
> downloads Gradle/dependencies and can take a few minutes.
>
> **Windows build note:** If the Gradle build fails with "Could not close
> incremental caches" from the Kotlin compiler (common when the Flutter pub
> cache lives on a different drive than the project), add this line to
> `android\gradle.properties` and rebuild:
>
> ```properties
> kotlin.incremental=false
> ```
>
> This disables Kotlin's incremental compilation cache and is the only change
> needed; the Dart code is unchanged.


---

## Running on an Android emulator

1. Open **Android Studio → Device Manager** and start a virtual device (e.g. a
   Pixel 7, API 34).
2. Confirm it is visible:

   ```powershell
   flutter devices
   ```

3. Run the app:

   ```powershell
   flutter run
   ```

   With multiple devices/emulators, target one explicitly:

   ```powershell
   flutter run -d <device-id>
   ```

Hot reload is available with `r`, hot restart with `R`, and the inspector with
`q` while `flutter run` is active.

You can also run on Windows desktop (note: the desktop build uses the same
Dart/SQLite layer; primary target is Android):

```powershell
flutter run -d windows
```

---

## Running tests

```powershell
flutter test
```

The suite covers:

- **Mood/emotion model serialization** (`test/mood_entry_model_test.dart`) —
  map/JSON round-trips, date normalization, optional notes, energy validation.
- **One-entry-per-day + persistence** (`test/mood_repository_test.dart`) —
  upsert behavior per local day, CRUD, range queries, and data surviving a
  close/reopen cycle on a real SQLite file.
- **Journal CRUD & search** (`test/journal_repository_test.dart`).
- **Statistics & empty-data analytics** (`test/stats_service_test.dart`) —
  counts, averages, top emotions, period filters, trend detection, and
  empty-input handling.
- **Data export to JSON** (`test/export_service_test.dart`) —
  payload schema versioning, ISO-8601 formatting, metadata and entry serialization.
- **End-to-end widget flows** (`test/app_widget_test.dart`) — first-launch empty
  state, the full check-in flow persisting exactly one entry, edit-instead-of-
  duplicate, insights empty state, confirmed clear-all-data, journal creation &
  search, calendar navigation, and theme mode toggling.
- **Phase 2 mood analysis** (`test/mood_analytics_service_test.dart`) — counts,
  averages, dominant mood, streaks, missing days, date filtering.
- **Phase 2 pattern detection** (`test/mood_pattern_service_test.dart`) —
  consistency, dominant mood, energy-motivation link, tense emotions, streaks.
- **Phase 2 insight generation** (`test/insight_generation_service_test.dart`) —
  card generation from patterns, empty-data handling, starter insight.
- **Phase 2 journal reflection** (`test/journal_reflection_service_test.dart`) —
  rule-based reflection, emotion/theme detection, reflection questions.
- **Phase 2 reflection repository** (`test/journal_reflection_repository_test.dart`) —
  CRUD, upsert, cascade delete, persistence across reopen.
- **Phase 2 database migration** (`test/database_migration_test.dart`) —
  `journal_reflections` table creation and foreign-key cascade.

Tests use `sqflite_common_ffi` (in-memory and temp-file databases) so they run
on desktop without a device.

Run a subset:

```powershell
flutter test test/stats_service_test.dart
flutter test --plain-name "full check-in flow"
```

---

## Project structure

```
lib/
├── main.dart                     # Entry point: init date symbols, load prefs, run app
├── app.dart                      # MoodlyApp root + AppServices (DI via InheritedWidget)
├── core/
│   ├── database/app_database.dart    # SQLite open/schema/migrations + error helper
│   ├── theme/
│   │   ├── app_colors.dart           # Brand palette
│   │   └── app_theme.dart            # Material 3 light & dark themes
│   └── utils/
│       ├── date_utils.dart           # Local-date keys, ranges, comparisons, greetings
│       └── formatters.dart           # intl date/time display formats
├── models/
│   ├── mood.dart                 # Mood enum (label, score, color, icon)
│   ├── emotion.dart              # Emotion enum + (de)serialization
│   ├── mood_entry.dart           # Mood check-in model (map/JSON)
│   └── journal_entry.dart        # Journal entry model (map/JSON)
├── repositories/
│   ├── mood_repository.dart      # One-check-in-per-day data access
│   ├── journal_repository.dart   # Journal data access + search
│   └── settings_repository.dart  # Theme preference (shared_preferences)
├── services/
│   ├── stats_service.dart        # Pure analytics (counts, averages, trends)
│   └── export_service.dart       # JSON payload + file write + share sheet
├── widgets/                      # Reusable UI: cards, states, selectors, dialogs, logo
└── features/
    ├── splash/                   # Branded launch screen
    ├── shell/                    # Bottom navigation host (IndexedStack)
    ├── home/                     # Dashboard
    ├── check_in/                 # Mood check-in form
    ├── calendar/                 # Month view + day detail
    ├── journal/                  # List/detail/editor
    ├── insights/                 # Charts + filters
    └── settings/                 # Theme, export, clear data, about
test/
├── helpers/test_harness.dart     # FFI/in-memory/temp-file DB factories
├── mood_entry_model_test.dart
├── mood_repository_test.dart
├── journal_repository_test.dart
├── stats_service_test.dart
├── export_service_test.dart
└── app_widget_test.dart
```

---

## Database & data model

SQLite is created at the platform databases path as `moodly.db`
(e.g. `/data/data/com.example.moodly/databases/moodly.db` on Android). Schema
creation is idempotent (`IF NOT EXISTS`-style via `CREATE TABLE` in `onCreate`)
and versioned so future migrations can run in `onUpgrade`.

### `mood_entries`

| Column       | Type    | Notes                                            |
| ------------ | ------- | ------------------------------------------------ |
| `id`         | INTEGER | Primary key, autoincrement                       |
| `date`       | TEXT    | `yyyy-MM-dd` **local** day, `UNIQUE` → one/day    |
| `mood`       | TEXT    | Stable mood name (`great` … `terrible`)          |
| `emotions`   | TEXT    | Comma-separated emotion names (may be empty)     |
| `energy`     | INTEGER | 1–5                                              |
| `note`       | TEXT    | Optional (nullable)                              |
| `created_at` | INTEGER | UTC epoch milliseconds                           |
| `updated_at` | INTEGER | UTC epoch milliseconds                           |

### `journal_entries`

| Column       | Type    | Notes                                 |
| ------------ | ------- | ------------------------------------- |
| `id`         | INTEGER | Primary key, autoincrement            |
| `date`       | TEXT    | `yyyy-MM-dd` local day (indexed)      |
| `title`      | TEXT    | Optional (nullable)                   |
| `body`       | TEXT    | Required, non-empty                   |
| `created_at` | INTEGER | UTC epoch milliseconds                |
| `updated_at` | INTEGER | UTC epoch milliseconds                |

### `journal_reflections` (Phase 2)

| Column                | Type    | Notes                                                                |
| --------------------- | ------- | -------------------------------------------------------------------- |
| `id`                  | INTEGER | Primary key, autoincrement                                           |
| `journal_entry_id`    | INTEGER | References `journal_entries(id)`, `ON DELETE CASCADE`                |
| `summary`             | TEXT    | Rule-based summary of the entry                                      |
| `detected_emotions`   | TEXT    | Comma-separated emotion labels detected in the text                  |
| `themes`              | TEXT    | Comma-separated themes (e.g. `challenging`, `positive`)              |
| `reflection_questions`| TEXT    | Comma-separated suggested reflection questions                       |
| `is_rule_based`       | INTEGER | 1 when produced by the local rule-based service                      |
| `created_at`          | INTEGER | UTC epoch milliseconds                                               |

**Local dates:** entries are keyed by the device's local calendar day
(`yyyy-MM-dd`) so "today" always matches what the user sees. Timestamps are
stored in UTC for durability; date comparisons happen on the normalized
date-only key, avoiding timezone drift.

> ⚠️ **Storage is local and is NOT encrypted by default.** SQLite files written
> by `sqflite` are plain files in the app's private storage. Anyone with root/
> device access (or a leaked backup) could read them. Treat the device and its
> backups accordingly. Encryption is a Phase 2 consideration.

---

## JSON export

Settings → **Export all data (JSON)** builds a single UTF-8 JSON document and
hands it to the OS share sheet (`share_plus`) after writing it to a temp file
(`path_provider`), so you can save it to cloud drive, email it, or copy it to
Files. The payload includes export metadata and **all** mood and journal
entries:

```jsonc
{
  "app": "Moodly",
  "tagline": "Your Daily Mood",
  "schemaVersion": 1,
  "exportedAt": "2026-10-28T16:32:00.000",
  "exportedAtLocal": "2026-10-28 16:32:00",
  "counts": { "moodEntries": 42, "journalEntries": 7 },
  "moodEntries": [
    {
      "id": 1,
      "date": "2026-10-28",
      "mood": "great",
      "moodLabel": "Great",
      "emotions": ["calm", "grateful"],
      "energy": 4,
      "note": "A nice day.",
      "createdAt": "2026-10-28T16:30:00.000",
      "updatedAt": "2026-10-28T16:30:00.000"
    }
  ],
  "journalEntries": [
    {
      "id": 1,
      "date": "2026-10-28",
      "title": "Reflection",
      "body": "…",
      "createdAt": "2026-10-28T17:00:00.000",
      "updatedAt": "2026-10-28T17:00:00.000"
    }
  ]
}
```

**Clear all data** deletes every row from both tables after an explicit
confirmation and refreshes the UI immediately.

---

## Phase 3 roadmap (not implemented)

Possible future enhancements, out of scope for Phase 2:

- **Optional remote AI** — a consent-gated AI provider behind the `AiService`
  abstraction, with explicit opt-in before any journal text leaves the device.
- **Encrypted local storage** — SQLCipher or similar for data at rest.
- **Reminders & streaks** — local notifications to encourage daily check-ins.
- **Richer analytics** — mood by weekday/hour, emotion correlations, custom
  date ranges, CSV/PDF reports.
- **Cloud sync** — opt-in, end-to-end-encrypted backup across devices.
- **Widgets & companions** — home-screen widgets and watch companions.

## Known limitations
- **English-only UI.** `flutter_localizations` is not included in Phase 1;
  date symbols are initialized for English.
- **Local-only, not encrypted.** No cloud sync, no accounts, no encryption at
  rest (see the storage note above).
- **Local timezone.** Days are whatever the device's local calendar reports;
  changing the device timezone/date changes what counts as "today" (by design).
- **Export** relies on the OS share sheet; if no share target is available the
  file is still written to a temporary location and its path is shown.
- **Analytics window.** The "trend" always compares the last 7 local days to
  the 7 before; charts only plot days that actually have a check-in.
- **Phase 1 scope:** no reminders/notifications, no CSV export, no backup
  restore/import.

---

## Phase 2 ideas

_Not implemented now — Phase 1 is local-first only._

- **Optional cloud sync** — opt-in, end-to-end-encrypted backup across devices.
- **Reminders & streaks** — local notifications to encourage a daily check-in.
- **Richer analytics** — mood-by-weekday/hour, emotion correlations, custom
  date ranges, CSV/PDF reports.
- **Privacy-conscious AI reflection assistant** — on-device or opt-in
  summarization of your own entries to surface patterns, with clear privacy
  controls and no data leaving the device by default.
- **Encrypted storage / encrypted exports.**
- **Widgets & watch companions**, mood tags, and richer media attachments.

---

## License

This project is provided as-is for the Moodly Phase 1 implementation.
