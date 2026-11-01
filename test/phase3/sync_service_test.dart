import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moodly/core/database/app_database.dart';
import 'package:moodly/core/network/api_client.dart';
import 'package:moodly/core/network/token_store.dart';
import 'package:moodly/models/journal_entry.dart';
import 'package:moodly/models/mood.dart';
import 'package:moodly/models/mood_entry.dart';
import 'package:moodly/repositories/journal_repository.dart';
import 'package:moodly/repositories/mood_repository.dart';
import 'package:moodly/repositories/settings_repository.dart';
import 'package:moodly/services/auth_service.dart';
import 'package:moodly/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_harness.dart';

/// Scriptable fake backend: answers /sync/push and /sync/pull from canned
/// payloads and records what was pushed.
class FakeBackend {
  Map<String, Object?> pushResponse = const {
    'accepted_moods': <String>[],
    'accepted_journals': <String>[],
    'mood_conflicts': <Object?>[],
    'journal_conflicts': <Object?>[],
    'journal_rejected_missing_consent': <String>[],
    'server_time': '2026-10-31T12:00:00Z',
  };
  Map<String, Object?> pullResponse = const {
    'moods': <Object?>[],
    'journals': <Object?>[],
    'server_time': '2026-10-31T12:00:00Z',
    'cursor': '2026-10-31T12:00:00Z',
  };

  final List<Map<String, Object?>> pushedBodies = [];
  final List<Object?> pushedMoods = [];
  final List<Object?> pushedJournals = [];
  Object? lastPullCursor;

  MockClient get client => MockClient((request) async {
    if (request.url.path == '/me') {
      return http.Response(
        '{"id": 7, "email": "u@moodly.test", "display_name": "U"}',
        200,
      );
    }
    if (request.url.path == '/sync/push') {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      pushedBodies.add(body);
      pushedMoods.addAll((body['moods'] as List?) ?? const []);
      pushedJournals.addAll((body['journals'] as List?) ?? const []);
      return http.Response(jsonEncode(pushResponse), 200);
    }
    if (request.url.path == '/sync/pull') {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      lastPullCursor = body['cursor'];
      return http.Response(jsonEncode(pullResponse), 200);
    }
    return http.Response('{"detail": "not found"}', 404);
  });
}

void main() {
  setupSqfliteFfiForTests();

  late AppDatabase database;
  late MoodRepository moods;
  late JournalRepository journals;
  late SettingsRepository settings;
  late FakeBackend backend;
  late SyncService sync;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await SettingsRepository.load();
    database = inMemoryDatabase();
    moods = MoodRepository(database);
    journals = JournalRepository(database);
    backend = FakeBackend();
    final tokens = InMemoryTokenStore();
    final api = ApiClient(
      baseUrl: 'http://localhost:8000',
      client: backend.client,
      tokenStore: tokens,
    );
    final auth = AuthService(api: api, tokenStore: tokens, settings: settings);
    await tokens.saveTokens(accessToken: 'a1', refreshToken: 'r1');
    await auth.restoreSession();
    sync = SyncService(
      api: api,
      auth: auth,
      settings: settings,
      moods: moods,
      journals: journals,
      database: database,
    );
  });

  tearDown(() => database.close());

  Future<void> enableSync({bool journalConsent = false}) async {
    await settings.setCloudSyncEnabled(true);
    await settings.setJournalUploadConsent(journalConsent);
  }

  group('SyncService gating', () {
    test('disabled when sync is off locally', () async {
      await sync.refresh();
      expect(sync.canSync, isFalse);
      expect(sync.status, SyncStatus.disabled);
      expect(await sync.syncNow(), isNull);
      expect(backend.pushedBodies, isEmpty);
    });

    test('push includes journal rows only with consent', () async {
      await enableSync(journalConsent: false);
      await moods.save(
        MoodEntry(date: DateTime(2026, 10, 28), mood: Mood.good, energy: 4),
      );
      await journals.insert(
        JournalEntry(date: DateTime(2026, 10, 28), body: 'private words'),
      );
      await sync.syncNow();

      expect(backend.pushedBodies.single['journal_upload_consent'], false);
      final pushedJournals = backend.pushedBodies.single['journals'] as List;
      expect(pushedJournals, isEmpty);
      // The mood row WAS pushed.
      final pushedMoods = backend.pushedBodies.single['moods'] as List;
      expect(pushedMoods, hasLength(1));
    });

    test('push includes journal rows with the double consent', () async {
      await enableSync(journalConsent: true);
      await journals.insert(
        JournalEntry(date: DateTime(2026, 10, 28), body: 'private words'),
      );
      await sync.syncNow();
      final pushedJournals = backend.pushedBodies.single['journals'] as List;
      expect(pushedJournals, hasLength(1));
      expect(backend.pushedBodies.single['journal_upload_consent'], true);
    });

    test('rejected journal consent is reported in the outcome', () async {
      await enableSync(journalConsent: true);
      await journals.insert(
        JournalEntry(date: DateTime(2026, 10, 28), body: 'private words'),
      );
      backend.pushResponse = {
        'accepted_moods': <String>[],
        'accepted_journals': <String>[],
        'mood_conflicts': <Object?>[],
        'journal_conflicts': <Object?>[],
        'journal_rejected_missing_consent': [
          (await journals.getAll()).first.clientId,
        ],
        'server_time': '2026-10-31T12:00:00Z',
      };
      final outcome = await sync.syncNow();
      expect(outcome!.rejectedJournals, 1);
      // Row stays pending for retry.
      expect(await journals.getPendingSync(), hasLength(1));
    });
  });

  group('SyncService push bookkeeping', () {
    test('accepted rows are marked synced; rejected stay pending', () async {
      await enableSync();
      final saved = await moods.save(
        MoodEntry(date: DateTime(2026, 10, 28), mood: Mood.good, energy: 4),
      );
      backend.pushResponse = {
        'accepted_moods': <String>[saved.clientId!],
        'accepted_journals': <String>[],
        'mood_conflicts': <Object?>[],
        'journal_conflicts': <Object?>[],
        'journal_rejected_missing_consent': <String>[],
        'server_time': '2026-10-31T12:00:00Z',
      };
      final outcome = await sync.syncNow();
      expect(outcome!.uploadedMoods, 1);
      expect(await moods.getPendingSync(), isEmpty);
      expect((await moods.getById(saved.id!))!.syncedAt, isNotNull);
    });

    test('unaccepted rows stay pending for the next run (retry)', () async {
      await enableSync();
      final saved = await moods.save(
        MoodEntry(date: DateTime(2026, 10, 28), mood: Mood.good, energy: 4),
      );
      // Server silently ignores the row (no accept entry).
      backend.pushResponse = {
        'accepted_moods': <String>[],
        'accepted_journals': <String>[],
        'mood_conflicts': <Object?>[],
        'journal_conflicts': <Object?>[],
        'journal_rejected_missing_consent': <String>[],
        'server_time': '2026-10-31T12:00:00Z',
      };
      await sync.syncNow();
      final pending = await moods.getPendingSync();
      expect(pending.single.id, saved.id);
    });

    test('a local edit after sync makes the row pending again', () async {
      await enableSync();
      final saved = await moods.save(
        MoodEntry(date: DateTime(2026, 10, 28), mood: Mood.good, energy: 4),
      );
      backend.pushResponse = {
        'accepted_moods': [saved.clientId],
        'accepted_journals': <String>[],
        'mood_conflicts': <Object?>[],
        'journal_conflicts': <Object?>[],
        'journal_rejected_missing_consent': <String>[],
        'server_time': '2026-10-31T12:00:00.000Z',
      };
      await sync.syncNow();
      expect(await moods.getPendingSync(), isEmpty);

      await moods.save(
        saved.copyWith(mood: Mood.great, energy: 5, updatedAt: DateTime.now()),
      );
      final pending = await moods.getPendingSync();
      expect(pending, hasLength(1));
      expect(pending.single.mood, Mood.great);
    });
  });

  group('SyncService conflicts (never silently overwrite newer data)', () {
    test('conflict with older local copy applies the server version', () async {
      await enableSync();
      final saved = await moods.save(
        MoodEntry(
          date: DateTime(2026, 10, 28),
          mood: Mood.good,
          energy: 4,
          updatedAt: DateTime(2026, 10, 27, 8),
        ),
      );
      backend.pushResponse = {
        'accepted_moods': <String>[],
        'accepted_journals': <String>[],
        'mood_conflicts': [
          {
            'client_id': saved.clientId,
            'server_version': {
              'client_id': saved.clientId,
              'date': '2026-10-28',
              'mood': 'great',
              'emotions': 'calm',
              'energy': 5,
              'note': null,
              // Newer than the local save (which is stamped "now").
              'server_updated_at': '2099-01-01T00:00:00Z',
            },
          },
        ],
        'journal_conflicts': <Object?>[],
        'journal_rejected_missing_consent': <String>[],
        'server_time': '2099-01-01T00:00:00Z',
      };
      final outcome = await sync.syncNow();
      expect(outcome!.resolvedConflicts, 1);
      expect(outcome.keptLocalConflicts, 0);
      final row = await moods.getById(saved.id!);
      expect(row!.mood, Mood.great);
      expect(row.energy, 5);
    });

    test('conflict with NEWER local copy keeps the local edit', () async {
      await enableSync();
      final saved = await moods.save(
        MoodEntry(
          date: DateTime(2026, 10, 28),
          mood: Mood.low,
          energy: 2,
          updatedAt: DateTime(2026, 10, 30, 20),
        ),
      );
      backend.pushResponse = {
        'accepted_moods': <String>[],
        'accepted_journals': <String>[],
        'mood_conflicts': [
          {
            'client_id': saved.clientId,
            'server_version': {
              'client_id': saved.clientId,
              'date': '2026-10-28',
              'mood': 'great',
              'emotions': 'calm',
              'energy': 5,
              'note': null,
              'server_updated_at': '2026-10-29T09:00:00Z',
            },
          },
        ],
        'journal_conflicts': <Object?>[],
        'journal_rejected_missing_consent': <String>[],
        'server_time': '2026-10-31T12:00:00Z',
      };
      final outcome = await sync.syncNow();
      expect(outcome!.keptLocalConflicts, 1);
      expect(outcome.resolvedConflicts, 0);
      final row = await moods.getById(saved.id!);
      expect(row!.mood, Mood.low); // local newer → untouched
    });
  });

  group('SyncService pull', () {
    test('a new cloud row is inserted locally', () async {
      await enableSync();
      backend.pullResponse = {
        'moods': [
          {
            'client_id': 'cli-cloud-0001',
            'date': '2026-10-26',
            'mood': 'good',
            'emotions': 'calm,joyful',
            'energy': 4,
            'note': null,
            'is_deleted': false,
            'server_updated_at': '2026-10-26T18:00:00Z',
          },
        ],
        'journals': <Object?>[],
        'server_time': '2026-10-31T12:00:00Z',
        'cursor': '2026-10-31T12:00:00Z',
      };
      final outcome = await sync.syncNow();
      expect(outcome!.downloadedMoods, 1);
      final all = await moods.getAll();
      expect(all, hasLength(1));
      expect(all.single.clientId, 'cli-cloud-0001');
      expect(all.single.mood, Mood.good);
      expect(all.single.syncedAt, isNotNull);
    });

    test('pulling the same row twice does not duplicate it', () async {
      await enableSync();
      backend.pullResponse = {
        'moods': [
          {
            'client_id': 'cli-cloud-0001',
            'date': '2026-10-26',
            'mood': 'good',
            'emotions': 'calm',
            'energy': 4,
            'note': null,
            'is_deleted': false,
            'server_updated_at': '2026-10-26T18:00:00Z',
          },
        ],
        'journals': <Object?>[],
        'server_time': '2026-10-31T12:00:00Z',
        'cursor': '2026-10-31T12:00:00Z',
      };
      await sync.syncNow();
      await sync.syncNow();
      expect(await moods.getAll(), hasLength(1));
    });

    test(
      'cloud deletion removes the local row (tombstone propagation)',
      () async {
        await enableSync();
        // First: insert the row via pull.
        backend.pullResponse = {
          'moods': [
            {
              'client_id': 'cli-cloud-0001',
              'date': '2026-10-26',
              'mood': 'good',
              'emotions': 'calm',
              'energy': 4,
              'note': null,
              'is_deleted': false,
              'server_updated_at': '2026-10-26T18:00:00Z',
            },
          ],
          'journals': <Object?>[],
          'server_time': '2026-10-31T12:00:00Z',
          'cursor': 'c1',
        };
        await sync.syncNow();
        expect(await moods.getAll(), hasLength(1));

        // Then: the server reports it deleted.
        backend.pullResponse = {
          'moods': [
            {
              'client_id': 'cli-cloud-0001',
              'date': '2026-10-26',
              'mood': 'good',
              'emotions': 'calm',
              'energy': 4,
              'note': null,
              'is_deleted': true,
              'server_updated_at': '2026-10-31T09:00:00Z',
            },
          ],
          'journals': <Object?>[],
          'server_time': '2026-10-31T12:00:00Z',
          'cursor': 'c2',
        };
        await sync.syncNow();
        expect(await moods.getAll(), isEmpty);
      },
    );

    test(
      'cursor is forwarded from settings and updated after the run',
      () async {
        await enableSync();
        await settings.setSyncCursor('c1');
        await sync.syncNow();
        expect(backend.lastPullCursor, 'c1');
        expect(settings.syncCursor, '2026-10-31T12:00:00Z');
      },
    );
  });

  group('SyncService deletions (tombstones)', () {
    test('a locally deleted synced row is pushed as a deletion', () async {
      await enableSync();
      final saved = await moods.save(
        MoodEntry(date: DateTime(2026, 10, 28), mood: Mood.good, energy: 4),
      );
      backend.pushResponse = {
        'accepted_moods': [saved.clientId],
        'accepted_journals': <String>[],
        'mood_conflicts': <Object?>[],
        'journal_conflicts': <Object?>[],
        'journal_rejected_missing_consent': <String>[],
        'server_time': '2026-10-31T12:00:00Z',
      };
      await sync.syncNow();

      await moods.delete(saved.id!);
      backend.pushedBodies.clear();
      backend.pushResponse = {
        'accepted_moods': [saved.clientId],
        'accepted_journals': <String>[],
        'mood_conflicts': <Object?>[],
        'journal_conflicts': <Object?>[],
        'journal_rejected_missing_consent': <String>[],
        'server_time': '2026-10-31T13:00:00Z',
      };
      await sync.syncNow();

      final pushedMoods = backend.pushedBodies.single['moods'] as List;
      expect(pushedMoods, hasLength(1));
      expect((pushedMoods.single as Map)['is_deleted'], true);
      // Tombstone was cleared after the server accepted it.
      final remaining = await SyncTombstones.pending(await database.open());
      expect(remaining, isEmpty);
    });

    test(
      'a locally deleted row always leaves a tombstone (resurrection guard)',
      () async {
        // Even a row that is currently pending gets a tombstone: after an
        // edit-then-delete sequence the server may still hold an older synced
        // version, and without a tombstone it would be re-downloaded and
        // "resurrect" locally. A tombstone for a row the server never saw is
        // harmless (it upserts a deletion marker).
        await enableSync();
        final saved = await moods.save(
          MoodEntry(date: DateTime(2026, 10, 28), mood: Mood.good, energy: 4),
        );
        await moods.delete(saved.id!);
        final remaining = await SyncTombstones.pending(await database.open());
        expect(remaining, hasLength(1));
        expect(remaining.single.clientId, saved.clientId);
      },
    );
  });

  group('SyncService error handling', () {
    test(
      'network failure sets error status and preserves local data',
      () async {
        await enableSync();
        await moods.save(
          MoodEntry(date: DateTime(2026, 10, 28), mood: Mood.good, energy: 4),
        );
        final failingTokens = InMemoryTokenStore()
          ..accessToken = 'a1'
          ..refreshToken = 'r1';
        final failingApi = ApiClient(
          baseUrl: 'http://localhost:8000',
          client: MockClient(
            (request) async => throw http.ClientException('offline'),
          ),
          tokenStore: failingTokens,
        );
        final failingAuth = AuthService(
          api: failingApi,
          tokenStore: failingTokens,
          settings: settings,
        );
        // Offline start with stored tokens → session kept optimistically.
        await failingAuth.restoreSession();
        expect(failingAuth.isSignedIn, isTrue);
        final failing = SyncService(
          api: failingApi,
          auth: failingAuth,
          settings: settings,
          moods: moods,
          journals: journals,
          database: database,
        );
        final outcome = await failing.syncNow();
        expect(outcome, isNull);
        expect(failing.status, SyncStatus.error);
        expect(failing.lastError, contains('offline'));
        // Local data untouched and still pending.
        expect(await moods.getAll(), hasLength(1));
        expect(await moods.getPendingSync(), hasLength(1));
      },
    );
  });
}
