import 'package:flutter/foundation.dart';

import '../core/database/app_database.dart';
import '../core/network/api_client.dart';
import '../core/utils/date_utils.dart';
import '../models/emotion.dart';
import '../models/journal_entry.dart';
import '../models/mood.dart';
import '../models/mood_entry.dart';
import '../repositories/journal_repository.dart';
import '../repositories/mood_repository.dart';
import '../repositories/settings_repository.dart';
import 'auth_service.dart';

/// Coarse sync state for the UI.
enum SyncStatus { disabled, idle, syncing, error }

/// Summary of one sync run, surfaced to the user.
class SyncOutcome {
  const SyncOutcome({
    this.uploadedMoods = 0,
    this.uploadedJournals = 0,
    this.downloadedMoods = 0,
    this.downloadedJournals = 0,
    this.resolvedConflicts = 0,
    this.keptLocalConflicts = 0,
    this.rejectedJournals = 0,
  });

  final int uploadedMoods;
  final int uploadedJournals;
  final int downloadedMoods;
  final int downloadedJournals;

  /// Conflicts where the cloud copy was newer and got applied locally.
  final int resolvedConflicts;

  /// Conflicts where the LOCAL copy was newer — it stays and will be pushed
  /// on the next sync. Nothing is silently overwritten either way.
  final int keptLocalConflicts;

  /// Journal rows the server refused because consent is not recorded.
  final int rejectedJournals;

  int get totalChanges =>
      uploadedMoods +
      uploadedJournals +
      downloadedMoods +
      downloadedJournals +
      resolvedConflicts;
}

/// Optional, user-controlled cloud synchronization (Phase 3).
///
/// Local-first guarantees:
/// - Runs only when [SettingsRepository.cloudSyncEnabled] and a session exist.
/// - Journal content is pushed only when [SettingsRepository.journalUploadConsent]
///   is true (the server re-checks the account's consent — double gate).
/// - Conflicts never silently overwrite newer data (last-write-wins by the
///   row's own `updated_at`; the loser stays pending or is kept).
/// - Failures never touch local data; the outcome records what happened and
///   the next run resumes from the stored cursor.
class SyncService extends ChangeNotifier {
  SyncService({
    required this._api,
    required this._auth,
    required this._settings,
    required this._moods,
    required this._journals,
    required this._database,
  });

  final ApiClient _api;
  final AuthService _auth;
  final SettingsRepository _settings;
  final MoodRepository _moods;
  final JournalRepository _journals;
  final AppDatabase _database;

  SyncStatus _status = SyncStatus.disabled;
  String? _lastError;
  int _pendingMoods = 0;
  int _pendingJournals = 0;
  bool _running = false;

  SyncStatus get status => _status;
  String? get lastError => _lastError;
  int get pendingMoods => _pendingMoods;
  int get pendingJournals => _pendingJournals;
  bool get canSync => _auth.isSignedIn && _settings.cloudSyncEnabled;
  DateTime? get lastSyncAt => _settings.lastSyncAt;

  /// Recomputes pending counts and status (call after local changes).
  Future<void> refresh() async {
    if (!canSync) {
      _status = SyncStatus.disabled;
      _pendingMoods = 0;
      _pendingJournals = 0;
      notifyListeners();
      return;
    }
    try {
      final moods = await _moods.getPendingSync();
      final journals = _settings.journalUploadConsent
          ? await _journals.getPendingSync()
          : <JournalEntry>[];
      _pendingMoods = moods.length;
      _pendingJournals = journals.length;
      if (_status != SyncStatus.syncing) {
        _status = _lastError == null ? SyncStatus.idle : SyncStatus.error;
      }
    } catch (_) {
      // DB not ready yet; keep previous state.
    }
    notifyListeners();
  }

  /// Runs one full push+pull cycle. Returns the outcome, or null when sync
  /// was skipped (disabled / not signed in). Never throws for network
  /// problems — those surface via [lastError] + [SyncStatus.error].
  Future<SyncOutcome?> syncNow() async {
    if (_running) return null;
    if (!canSync) {
      await refresh();
      return null;
    }
    _running = true;
    _status = SyncStatus.syncing;
    _lastError = null;
    notifyListeners();

    try {
      final outcome = await _run();
      _status = SyncStatus.idle;
      await _settings.setLastSyncAt(DateTime.now());
      await refresh();
      return outcome;
    } on ApiException catch (e) {
      _lastError = e.isOffline
          ? 'You are offline. Moodly keeps working — sync will resume when '
                'you reconnect.'
          : e.message;
      _status = SyncStatus.error;
      notifyListeners();
      return null;
    } catch (e) {
      _lastError = 'Sync failed unexpectedly. Your local data is untouched.';
      _status = SyncStatus.error;
      notifyListeners();
      return null;
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  Future<SyncOutcome> _run() async {
    var uploadedMoods = 0;
    var uploadedJournals = 0;
    var resolvedConflicts = 0;
    var keptLocalConflicts = 0;
    var rejectedJournals = 0;

    // --- push pending rows + tombstones ------------------------------------
    final pendingMoods = await _moods.getPendingSync();
    final journalConsent = _settings.journalUploadConsent;
    final pendingJournals = journalConsent
        ? await _journals.getPendingSync()
        : <JournalEntry>[];

    final tombstones = await SyncTombstones.pending(await _database.open());
    final moodTombstones = tombstones
        .where((t) => t.kind == SyncTombstoneKind.mood)
        .toList();
    final journalTombstones = journalConsent
        ? tombstones.where((t) => t.kind == SyncTombstoneKind.journal).toList()
        : const <({String kind, String clientId})>[];

    final moodPayload = <Map<String, Object?>>[
      ...pendingMoods.map(_moodToJson),
      ...moodTombstones.map((t) => _tombstoneToJson(t.clientId, kind: 'mood')),
    ];
    final journalPayload = <Map<String, Object?>>[
      ...pendingJournals.map(_journalToJson),
      ...journalTombstones.map(
        (t) => _tombstoneToJson(t.clientId, kind: 'journal', body: ''),
      ),
    ];

    if (moodPayload.isNotEmpty || journalPayload.isNotEmpty) {
      final push = await _api.post(
        '/sync/push',
        body: {
          'moods': moodPayload,
          'journals': journalPayload,
          'journal_upload_consent': journalConsent,
        },
      );

      final acceptedMoods = _asStringSet(push['accepted_moods']);
      final acceptedJournals = _asStringSet(push['accepted_journals']);
      rejectedJournals = _asStringSet(push['journal_rejected_missing_consent'])
          .length;

      // Rows the server accepted are now synced (server time is the marker).
      final serverTime = _parseDateTime(push['server_time']) ?? DateTime.now();
      final moodIdsToMark = pendingMoods
          .where(
            (e) => e.clientId != null && acceptedMoods.contains(e.clientId),
          )
          .map((e) => e.id)
          .whereType<int>()
          .toList();
      await _moods.markSynced(moodIdsToMark, serverTime);
      final journalIdsToMark = pendingJournals
          .where(
            (e) => e.clientId != null && acceptedJournals.contains(e.clientId),
          )
          .map((e) => e.id)
          .whereType<int>()
          .toList();
      await _journals.markSynced(journalIdsToMark, serverTime);
      uploadedMoods = moodIdsToMark.length;
      uploadedJournals = journalIdsToMark.length;

      final db = await _database.open();
      await SyncTombstones.clear(
        db,
        SyncTombstoneKind.mood,
        moodTombstones
            .where((t) => acceptedMoods.contains(t.clientId))
            .map((t) => t.clientId),
      );
      await SyncTombstones.clear(
        db,
        SyncTombstoneKind.journal,
        journalTombstones
            .where((t) => acceptedJournals.contains(t.clientId))
            .map((t) => t.clientId),
      );

      // Conflicts: apply the server copy only when it is newer.
      for (final raw in _asList(push['mood_conflicts'])) {
        final resolved = await _resolveMoodConflict(raw);
        resolved ? resolvedConflicts++ : keptLocalConflicts++;
      }
      for (final raw in _asList(push['journal_conflicts'])) {
        final resolved = await _resolveJournalConflict(raw);
        resolved ? resolvedConflicts++ : keptLocalConflicts++;
      }
    }

    // --- pull changes since the cursor --------------------------------------
    final pull = await _api.post(
      '/sync/pull',
      body: {'cursor': _settings.syncCursor},
    );

    var downloadedMoods = 0;
    var downloadedJournals = 0;
    final serverTime = _parseDateTime(pull['server_time']);

    for (final raw in _asList(pull['moods'])) {
      if (raw is! Map) continue;
      final row = Map<String, Object?>.from(raw);
      final isDeleted = row['is_deleted'] == true;
      final clientId = row['client_id']?.toString();
      final updatedAt = _parseDateTime(row['server_updated_at']);
      if (clientId == null || updatedAt == null) continue;
      if (isDeleted) {
        final local = await _localMoodByClientId(clientId);
        if (local != null && !local.updatedAt.isAfter(updatedAt)) {
          await _moods.deleteByClientId(clientId);
          downloadedMoods++;
        }
        continue;
      }
      final applied = await _moods.applyCloudRow(
        _moodFromCloud(row),
        serverUpdatedAt: updatedAt,
      );
      if (applied != null) downloadedMoods++;
    }

    for (final raw in _asList(pull['journals'])) {
      if (raw is! Map) continue;
      final row = Map<String, Object?>.from(raw);
      final isDeleted = row['is_deleted'] == true;
      final clientId = row['client_id']?.toString();
      final updatedAt = _parseDateTime(row['server_updated_at']);
      if (clientId == null || updatedAt == null) continue;
      if (isDeleted) {
        final local = await _localJournalByClientId(clientId);
        if (local != null && !local.updatedAt.isAfter(updatedAt)) {
          await _journals.deleteByClientId(clientId);
          downloadedJournals++;
        }
        continue;
      }
      final applied = await _journals.applyCloudRow(
        _journalFromCloud(row),
        serverUpdatedAt: updatedAt,
      );
      if (applied != null) downloadedJournals++;
    }

    final cursor = pull['cursor'];
    if (cursor is String && cursor.isNotEmpty) {
      await _settings.setSyncCursor(cursor);
    } else if (serverTime != null) {
      await _settings.setSyncCursor(serverTime.toUtc().toIso8601String());
    }

    return SyncOutcome(
      uploadedMoods: uploadedMoods,
      uploadedJournals: uploadedJournals,
      downloadedMoods: downloadedMoods,
      downloadedJournals: downloadedJournals,
      resolvedConflicts: resolvedConflicts,
      keptLocalConflicts: keptLocalConflicts,
      rejectedJournals: rejectedJournals,
    );
  }

  // --- conflict resolution ----------------------------------------------------

  Future<bool> _resolveMoodConflict(Object? raw) async {
    if (raw is! Map) return false;
    final clientId = raw['client_id']?.toString();
    final version = raw['server_version'];
    if (clientId == null || version is! Map) return false;
    final serverUpdatedAt = _parseDateTime(version['server_updated_at']);
    if (serverUpdatedAt == null) return false;

    final local = await _localMoodByClientId(clientId);
    if (local == null) {
      // We never had it locally (deleted here) → adopt server copy.
      await _moods.applyCloudRow(
        _moodFromCloud(Map<String, Object?>.from(version)),
        serverUpdatedAt: serverUpdatedAt,
      );
      return true;
    }
    if (local.updatedAt.isAfter(serverUpdatedAt)) {
      return false; // local newer → keep local (stays pending for push)
    }
    await _moods.applyCloudRow(
      _moodFromCloud(Map<String, Object?>.from(version)),
      serverUpdatedAt: serverUpdatedAt,
    );
    return true;
  }

  Future<bool> _resolveJournalConflict(Object? raw) async {
    if (raw is! Map) return false;
    final clientId = raw['client_id']?.toString();
    final version = raw['server_version'];
    if (clientId == null || version is! Map) return false;
    final serverUpdatedAt = _parseDateTime(version['server_updated_at']);
    if (serverUpdatedAt == null) return false;

    final local = await _localJournalByClientId(clientId);
    if (local == null) {
      await _journals.applyCloudRow(
        _journalFromCloud(Map<String, Object?>.from(version)),
        serverUpdatedAt: serverUpdatedAt,
      );
      return true;
    }
    if (local.updatedAt.isAfter(serverUpdatedAt)) return false;
    await _journals.applyCloudRow(
      _journalFromCloud(Map<String, Object?>.from(version)),
      serverUpdatedAt: serverUpdatedAt,
    );
    return true;
  }

  // --- payload helpers ----------------------------------------------------------

  Map<String, Object?> _moodToJson(MoodEntry e) => {
    'client_id': e.clientId,
    'date': AppDates.dateKey(e.date),
    'mood': e.mood.storageName,
    'emotions': e.emotions.map((x) => x.storageName).toList(),
    'energy': e.energy,
    'note': e.note,
    'updated_at': e.updatedAt.toUtc().toIso8601String(),
    'is_deleted': false,
  };

  Map<String, Object?> _journalToJson(JournalEntry e) => {
    'client_id': e.clientId,
    'date': AppDates.dateKey(e.date),
    'title': e.title,
    'body': e.body,
    'updated_at': e.updatedAt.toUtc().toIso8601String(),
    'is_deleted': false,
  };

  /// Tombstone rows keep the required schema shape with neutral content —
  /// the original content is gone by design (deleted locally).
  Map<String, Object?> _tombstoneToJson(
    String clientId, {
    required String kind,
    String? body,
  }) => {
    'client_id': clientId,
    'date': AppDates.dateKey(DateTime.now()),
    if (kind == 'mood') ...{
      'mood': 'okay',
      'emotions': <String>[],
      'energy': 3,
      'note': null,
    } else ...{
      'title': null,
      'body': body ?? '',
    },
    'updated_at': DateTime.now().toUtc().toIso8601String(),
    'is_deleted': true,
  };

  MoodEntry _moodFromCloud(Map<String, Object?> row) => MoodEntry(
    date: AppDates.parseDateKey(row['date'] as String),
    mood: Mood.fromStorageName(row['mood'] as String?),
    emotions: parseEmotions(
      row['emotions'] is String ? row['emotions'] as String : null,
    ),
    energy: (row['energy'] as num?)?.toInt() ?? 3,
    note: row['note'] as String?,
    updatedAt: _parseDateTime(row['server_updated_at']) ?? DateTime.now(),
    clientId: row['client_id'] as String?,
    syncedAt: _parseDateTime(row['server_updated_at']),
  );

  JournalEntry _journalFromCloud(Map<String, Object?> row) => JournalEntry(
    date: AppDates.parseDateKey(row['date'] as String),
    title: row['title'] as String?,
    body: (row['body'] as String?) ?? '',
    updatedAt: _parseDateTime(row['server_updated_at']) ?? DateTime.now(),
    clientId: row['client_id'] as String?,
    syncedAt: _parseDateTime(row['server_updated_at']),
  );

  Future<MoodEntry?> _localMoodByClientId(String clientId) async {
    final all = await _moods.getAll();
    for (final e in all) {
      if (e.clientId == clientId) return e;
    }
    return null;
  }

  Future<JournalEntry?> _localJournalByClientId(String clientId) async {
    final all = await _journals.getAll();
    for (final e in all) {
      if (e.clientId == clientId) return e;
    }
    return null;
  }

  static Set<String> _asStringSet(Object? raw) =>
      raw is List ? raw.map((e) => e.toString()).toSet() : <String>{};

  static List<Object?> _asList(Object? raw) =>
      raw is List ? raw : const <Object?>[];

  static DateTime? _parseDateTime(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }
}
