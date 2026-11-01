import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import '../models/client_id.dart';
import '../models/journal_entry.dart';
import 'mood_repository.dart';

/// Data access for standalone journal entries (any number per day).
///
/// Phase 3 sync support mirrors [MoodRepository]: stable `client_id`,
/// `synced_at` pending marker, and delete tombstones.
class JournalRepository {
  JournalRepository(this._db);

  static const String table = 'journal_entries';

  final AppDatabase _db;

  Future<Database> get _database => _db.open();

  /// All entries, newest first. When [query] is provided only entries whose
  /// title or body contain it (case-insensitive) are returned.
  Future<List<JournalEntry>> getAll({String? query}) async {
    final db = await _database;
    final q = query?.trim() ?? '';
    final rows = await db.query(
      table,
      where: q.isEmpty ? null : 'LOWER(title) LIKE ? OR LOWER(body) LIKE ?',
      whereArgs: q.isEmpty
          ? null
          : ['%${q.toLowerCase()}%', '%${q.toLowerCase()}%'],
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(JournalEntry.fromMap).toList();
  }

  Future<JournalEntry?> getById(int id) async {
    final db = await _database;
    final rows = await db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : JournalEntry.fromMap(rows.first);
  }

  Future<int> count() async {
    final db = await _database;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Inserts a new entry and returns it with its assigned id. A stable
  /// `client_id` is assigned and the row starts pending-sync.
  Future<JournalEntry> insert(JournalEntry entry) async {
    final db = await _database;
    final now = DateTime.now();
    final toInsert = entry.copyWith(
      createdAt: now,
      updatedAt: now,
      clientId: entry.clientId ?? ClientId.generate(),
      clearSyncedAt: true,
    );
    final id = await db.insert(table, toInsert.toMap());
    return toInsert.copyWith(id: id);
  }

  /// Updates an existing entry. Throws if [entry] has no id. Marks the row
  /// pending-sync (local change not yet uploaded).
  Future<void> update(JournalEntry entry) async {
    final id = entry.id;
    if (id == null) {
      throw ArgumentError('Cannot update a journal entry without an id');
    }
    final db = await _database;
    await db.transaction((txn) async {
      final existing = await txn.query(
        table,
        columns: ['id', 'client_id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final clientId = existing.isEmpty
          ? null
          : existing.first['client_id'] as String?;
      await txn.update(
        table,
        entry
            .copyWith(
              updatedAt: DateTime.now(),
              clientId: clientId ?? entry.clientId ?? ClientId.generate(),
              clearSyncedAt: true,
            )
            .toMap(),
        where: 'id = ?',
        whereArgs: [id],
      );
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
        await SyncTombstones.record(txn, SyncTombstoneKind.journal, clientId);
      }
      await txn.delete(table, where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Removes every journal entry (used by "clear all data").
  Future<void> deleteAll() async {
    final db = await _database;
    await db.delete(table);
  }

  // --- Phase 3 sync support ---------------------------------------------------

  /// Rows with local changes not yet acknowledged by the server.
  Future<List<JournalEntry>> getPendingSync() async {
    final db = await _database;
    final rows = await db.query(
      table,
      where: 'synced_at IS NULL',
      orderBy: 'updated_at ASC',
    );
    return rows.map(JournalEntry.fromMap).toList();
  }

  /// Marks rows as accepted by the server at [syncedAt].
  Future<void> markSynced(Iterable<int> ids, DateTime syncedAt) async {
    final idList = ids.toList();
    if (idList.isEmpty) return;
    final db = await _database;
    await db.transaction((txn) async {
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

  /// Applies a server row with last-write-wins rules (see MoodRepository).
  Future<JournalEntry?> applyCloudRow(
    JournalEntry cloud, {
    required DateTime serverUpdatedAt,
  }) async {
    final db = await _database;
    return db.transaction<JournalEntry?>((txn) async {
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
      final existing = JournalEntry.fromMap(byClientId.first);
      if (existing.updatedAt.isAfter(cloud.updatedAt)) {
        return null; // local newer → keep local, stays pending
      }
      final merged = existing.copyWith(
        date: cloud.date,
        title: cloud.title,
        clearTitle: cloud.title == null,
        body: cloud.body,
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

  /// Deletes a local row by its stable sync id (cloud-reported deletions).
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
