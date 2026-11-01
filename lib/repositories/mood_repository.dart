import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import '../core/utils/date_utils.dart';
import '../models/client_id.dart';
import '../models/mood_entry.dart';

/// Data access for daily mood check-ins.
///
/// Business rule: **at most one check-in per local calendar day**. [save]
/// enforces this inside a transaction by looking up any existing row for the
/// entry's day and updating it in place, so callers never create duplicates.
///
/// Phase 3 sync support: every row carries a stable `client_id` (generated on
/// first save) and `synced_at` (null = local changes pending upload). Deletes
/// of previously synced rows leave a tombstone so other devices learn about
/// the deletion.
class MoodRepository {
  MoodRepository(this._db);

  static const String table = 'mood_entries';

  final AppDatabase _db;

  Future<Database> get _database => _db.open();

  /// All check-ins, newest day first.
  Future<List<MoodEntry>> getAll() async {
    final db = await _database;
    final rows = await db.query(table, orderBy: 'date DESC, id DESC');
    return rows.map(MoodEntry.fromMap).toList();
  }

  /// Check-ins between [from] and [to] (inclusive, local days), oldest first.
  Future<List<MoodEntry>> getInRange(DateTime from, DateTime to) async {
    final db = await _database;
    final rows = await db.query(
      table,
      where: 'date BETWEEN ? AND ?',
      whereArgs: [AppDates.dateKey(from), AppDates.dateKey(to)],
      orderBy: 'date ASC',
    );
    return rows.map(MoodEntry.fromMap).toList();
  }

  /// The check-in for a given local day, or `null`.
  Future<MoodEntry?> getByDate(DateTime date) async {
    final db = await _database;
    final rows = await db.query(
      table,
      where: 'date = ?',
      whereArgs: [AppDates.dateKey(date)],
      limit: 1,
    );
    return rows.isEmpty ? null : MoodEntry.fromMap(rows.first);
  }

  Future<MoodEntry?> getById(int id) async {
    final db = await _database;
    final rows = await db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : MoodEntry.fromMap(rows.first);
  }

  Future<int> count() async {
    final db = await _database;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Saves a check-in, keeping one row per local calendar day.
  ///
  /// If an entry already exists for the same day it is updated in place
  /// (preserving its id and creation time). Returns the persisted entry.
  /// Every save marks the row as pending sync (`synced_at = null`) and
  /// assigns a stable `client_id` when missing.
  Future<MoodEntry> save(MoodEntry entry) async {
    final db = await _database;
    final now = DateTime.now();
    final normalized = entry.copyWith(date: AppDates.dateOnly(entry.date));

    return db.transaction<MoodEntry>((txn) async {
      final existing = await txn.query(
        table,
        columns: ['id', 'created_at', 'client_id'],
        where: 'date = ?',
        whereArgs: [AppDates.dateKey(normalized.date)],
        limit: 1,
      );

      if (existing.isEmpty) {
        final toInsert = normalized.copyWith(
          createdAt: now,
          updatedAt: now,
          clientId: normalized.clientId ?? ClientId.generate(),
          clearSyncedAt: true,
        );
        final id = await txn.insert(table, toInsert.toMap());
        return toInsert.copyWith(id: id);
      }

      final existingId = existing.first['id']! as int;
      final existingCreatedMs = existing.first['created_at']! as int;
      final existingClientId = existing.first['client_id'] as String?;
      final updated = normalized.copyWith(
        id: existingId,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          existingCreatedMs,
          isUtc: true,
        ).toLocal(),
        updatedAt: now,
        clientId:
            existingClientId ?? normalized.clientId ?? ClientId.generate(),
        clearSyncedAt: true, // local edit → needs upload again
      );
      await txn.update(
        table,
        updated.toMap(),
        where: 'id = ?',
        whereArgs: [existingId],
      );
      return updated;
    });
  }

  Future<void> delete(int id) async {
    final db = await _database;
    final existing = await db.query(
      table,
      columns: ['id', 'client_id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (existing.isEmpty) return;
    final clientId = existing.first['client_id'] as String?;
    await db.transaction((txn) async {
      if (clientId != null) {
        await SyncTombstones.record(txn, SyncTombstoneKind.mood, clientId);
      }
      await txn.delete(table, where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Removes every mood check-in (used by "clear all data").
  Future<void> deleteAll() async {
    final db = await _database;
    await db.delete(table);
  }

  // --- Phase 3 sync support ---------------------------------------------------

  /// Rows with local changes not yet acknowledged by the server.
  Future<List<MoodEntry>> getPendingSync() async {
    final db = await _database;
    final rows = await db.query(
      table,
      where: 'synced_at IS NULL',
      orderBy: 'updated_at ASC',
    );
    return rows.map(MoodEntry.fromMap).toList();
  }

  /// Marks rows as accepted by the server at [syncedAt].
  Future<void> markSynced(Iterable<int> ids, DateTime syncedAt) async {
    final idList = ids.toList();
    if (idList.isEmpty) return;
    final db = await _database;
    await db.transaction((txn) async {
      // SQLite parameter limits: chunk to stay well below 999.
      for (var i = 0; i < idList.length; i += 400) {
        final chunk = idList.sublist(
          i,
          i + 400 > idList.length ? idList.length : i + 400,
        );
        final placeholders = List.filled(chunk.length, '?').join(',');
        await txn.rawUpdate(
          'UPDATE $table SET synced_at = ? WHERE id IN ($placeholders)',
          [syncedAt.toUtc().millisecondsSinceEpoch, ...chunk],
        );
      }
    });
  }

  /// Applies a server row to the local database using last-write-wins rules.
  ///
  /// Returns the resulting local state:
  /// - `null` → local copy kept (local is newer; stays pending for upload)
  /// - the upserted [MoodEntry] → cloud copy stored/updated
  Future<MoodEntry?> applyCloudRow(
    MoodEntry cloud, {
    required DateTime serverUpdatedAt,
  }) async {
    final db = await _database;
    return db.transaction<MoodEntry?>((txn) async {
      final byClientId = await txn.query(
        table,
        where: 'client_id = ?',
        whereArgs: [cloud.clientId],
        limit: 1,
      );
      if (byClientId.isEmpty) {
        final toInsert = cloud.copyWith(syncedAt: serverUpdatedAt);
        final id = await txn.insert(table, toInsert.toMap());
        return toInsert.copyWith(id: id);
      }
      final existing = MoodEntry.fromMap(byClientId.first);
      if (existing.updatedAt.isAfter(cloud.updatedAt)) {
        // Local copy is newer: keep it; it stays pending for the next push.
        return null;
      }
      final merged = existing.copyWith(
        date: cloud.date,
        mood: cloud.mood,
        emotions: cloud.emotions,
        energy: cloud.energy,
        note: cloud.note,
        clearNote: cloud.note == null,
        createdAt: existing.createdAt,
        updatedAt: cloud.updatedAt,
        syncedAt: serverUpdatedAt,
      );
      await txn.update(
        table,
        merged.toMap(),
        where: 'id = ?',
        whereArgs: [existing.id],
      );
      return merged;
    });
  }

  /// Deletes a local row by its stable sync id. Used when the cloud reports a
  /// deletion (tombstone) that is newer than the local copy.
  Future<bool> deleteByClientId(String clientId) async {
    final db = await _database;
    final removed = await db.delete(
      table,
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
    return removed > 0;
  }
}

/// Kinds of tombstoned rows kept for sync.
class SyncTombstoneKind {
  static const String mood = 'mood';
  static const String journal = 'journal';
}

/// Tombstones for locally deleted rows that still must reach the cloud.
class SyncTombstones {
  static const String table = 'sync_tombstones';

  /// Records (idempotently) that [clientId] was deleted locally.
  static Future<void> record(
    DatabaseExecutor db,
    String kind,
    String clientId,
  ) async {
    await db.insert(table, {
      'kind': kind,
      'client_id': clientId,
      'deleted_at': DateTime.now().toUtc().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// All pending tombstones, oldest first.
  static Future<List<({String kind, String clientId})>> pending(
    Database db,
  ) async {
    final rows = await db.query(table, orderBy: 'deleted_at ASC');
    return rows
        .map(
          (r) =>
              (kind: r['kind'] as String, clientId: r['client_id'] as String),
        )
        .toList();
  }

  /// Removes tombstones after the server accepted them.
  static Future<void> clear(
    Database db,
    String kind,
    Iterable<String> clientIds,
  ) async {
    final ids = clientIds.toList();
    for (var i = 0; i < ids.length; i += 400) {
      final chunk = ids.sublist(i, i + 400 > ids.length ? ids.length : i + 400);
      final placeholders = List.filled(chunk.length, '?').join(',');
      await db.delete(
        table,
        where: 'kind = ? AND client_id IN ($placeholders)',
        whereArgs: [kind, ...chunk],
      );
    }
  }
}
