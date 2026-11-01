import 'package:flutter_test/flutter_test.dart';
import 'package:moodly/core/database/app_database.dart';
import 'package:moodly/models/client_id.dart';
import 'package:moodly/models/mood.dart';
import 'package:moodly/models/mood_entry.dart';
import 'package:moodly/models/report.dart';
import 'package:moodly/repositories/journal_repository.dart';
import 'package:moodly/repositories/mood_repository.dart';
import 'package:moodly/repositories/report_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_harness.dart';

/// Creates a Phase 2 (schema v2) database at [path] with legacy rows that
/// have no sync columns, mimicking an existing user upgrading to Phase 3.
Future<void> createLegacyV2Database(String path) async {
  final db = await databaseFactoryFfiNoIsolate.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE mood_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL UNIQUE,
            mood TEXT NOT NULL,
            emotions TEXT NOT NULL DEFAULT '',
            energy INTEGER NOT NULL,
            note TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE journal_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            title TEXT,
            body TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE journal_reflections (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            journal_entry_id INTEGER NOT NULL,
            summary TEXT NOT NULL,
            detected_emotions TEXT NOT NULL DEFAULT '',
            themes TEXT NOT NULL DEFAULT '',
            reflection_questions TEXT NOT NULL DEFAULT '',
            is_rule_based INTEGER NOT NULL DEFAULT 1,
            created_at INTEGER NOT NULL,
            FOREIGN KEY (journal_entry_id) REFERENCES journal_entries(id)
              ON DELETE CASCADE
          )
        ''');
      },
    ),
  );
  final nowMs = DateTime(2026, 10, 15, 12).toUtc().millisecondsSinceEpoch;
  await db.insert('mood_entries', {
    'date': '2026-10-15',
    'mood': 'good',
    'emotions': 'calm,happy',
    'energy': 4,
    'note': 'legacy check-in',
    'created_at': nowMs,
    'updated_at': nowMs,
  });
  await db.insert('mood_entries', {
    'date': '2026-10-16',
    'mood': 'low',
    'emotions': '',
    'energy': 2,
    'note': null,
    'created_at': nowMs,
    'updated_at': nowMs,
  });
  final journalId = await db.insert('journal_entries', {
    'date': '2026-10-15',
    'title': 'Legacy journal',
    'body': 'An old journal entry from Phase 2.',
    'created_at': nowMs,
    'updated_at': nowMs,
  });
  await db.insert('journal_reflections', {
    'journal_entry_id': journalId,
    'summary': 'Legacy reflection.',
    'detected_emotions': 'calm',
    'themes': 'reflective',
    'reflection_questions': 'Q1?,Q2?,Q3?',
    'is_rule_based': 1,
    'created_at': nowMs,
  });
  await db.close();
}

void main() {
  setupSqfliteFfiForTests();

  group('Schema v2 → v3 migration (Phase 3 upgrade path)', () {
    test(
      'existing mood rows are preserved with generated client ids',
      () async {
        final env = fileDatabase();
        addTearDown(env.cleanup);
        await env.database.close(); // close the auto-created v3 db
        await createLegacyV2Database(env.path);

        final database = AppDatabase(
          dbFactory: databaseFactoryFfiNoIsolate,
          dbPath: env.path,
        );
        addTearDown(database.close);
        final repo = MoodRepository(database);
        final all = await repo.getAll();
        expect(all, hasLength(2));
        final first = all.firstWhere((e) => e.date.day == 15);
        expect(first.mood, Mood.good);
        expect(first.note, 'legacy check-in');
        expect(first.emotions.map((e) => e.storageName), ['calm', 'happy']);
        // Backfilled stable ids — unique per row.
        final ids = all.map((e) => e.clientId).toSet();
        expect(ids, hasLength(2));
        expect(all.every((e) => e.clientId != null), isTrue);
        // Backfilled rows start as pending (never uploaded).
        expect(all.every((e) => e.needsSync), isTrue);
        // Opening again must not regenerate ids (idempotent backfill).
        await database.close();
        final reopened = AppDatabase(
          dbFactory: databaseFactoryFfiNoIsolate,
          dbPath: env.path,
        );
        addTearDown(reopened.close);
        final again = await MoodRepository(reopened).getAll();
        expect(
          again.map((e) => e.clientId).toSet(),
          ids,
          reason: 'client ids must be stable across restarts',
        );
      },
    );

    test(
      'existing journal entries and reflections survive the upgrade',
      () async {
        final env = fileDatabase();
        addTearDown(env.cleanup);
        await env.database.close();
        await createLegacyV2Database(env.path);

        final database = AppDatabase(
          dbFactory: databaseFactoryFfiNoIsolate,
          dbPath: env.path,
        );
        addTearDown(database.close);
        final journals = await JournalRepository(database).getAll();
        expect(journals, hasLength(1));
        expect(journals.single.title, 'Legacy journal');
        expect(journals.single.body, contains('Phase 2'));
        expect(journals.single.clientId, isNotNull);

        final db = await database.open();
        final reflections = await db.query('journal_reflections');
        expect(reflections, hasLength(1));
        expect(reflections.single['summary'], 'Legacy reflection.');
        // Old reflection rows get the new default columns.
        expect(reflections.single['provider'], 'local_rules');
      },
    );

    test('new Phase 3 tables exist after migration', () async {
      final env = fileDatabase();
      addTearDown(env.cleanup);
      await env.database.close();
      await createLegacyV2Database(env.path);

      final database = AppDatabase(
        dbFactory: databaseFactoryFfiNoIsolate,
        dbPath: env.path,
      );
      addTearDown(database.close);
      final db = await database.open();
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final names = tables.map((t) => t['name']).toSet();
      expect(names, contains('generated_reports'));
      expect(names, contains('sync_tombstones'));
    });

    test('migrated database supports full Phase 3 round trips', () async {
      final env = fileDatabase();
      addTearDown(env.cleanup);
      await env.database.close();
      await createLegacyV2Database(env.path);

      final database = AppDatabase(
        dbFactory: databaseFactoryFfiNoIsolate,
        dbPath: env.path,
      );
      addTearDown(database.close);

      // Saving a new check-in on the migrated schema.
      final saved = await MoodRepository(database).save(
        MoodEntry(date: DateTime(2026, 10, 20), mood: Mood.great, energy: 5),
      );
      expect(saved.clientId, isNotNull);

      // Reports can be stored (unique per kind + period start).
      final reportRepo = ReportRepository(database);
      await reportRepo.save(
        MoodReport(
          kind: 'weekly',
          periodStart: DateTime(2026, 10, 19),
          periodEnd: DateTime(2026, 10, 20),
          periodLabel: '19/10/2026 – 20/10/2026',
          data: const {
            'stats': {'totalCheckins': 2},
          },
          createdAt: DateTime(2026, 10, 20),
        ),
      );
      final stored = await reportRepo.getAll();
      expect(stored, hasLength(1));
      final stats = stored.single.data['stats'] as Map<String, Object?>;
      expect(stats['totalCheckins'], 2);
    });
  });

  group('ClientId', () {
    test('generates UUIDv4-format unique ids', () {
      final ids = List.generate(200, (_) => ClientId.generate());
      expect(ids.toSet(), hasLength(200), reason: 'ids must be unique');
      final uuidV4 = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
        r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      for (final id in ids) {
        expect(id, matches(uuidV4), reason: 'must be a UUIDv4: $id');
      }
    });
  });
}
