import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import '../core/utils/date_utils.dart';
import '../models/mood_entry.dart';

/// Data access for daily mood check-ins.
///
/// Business rule: **at most one check-in per local calendar day**. [save]
/// enforces this inside a transaction by looking up any existing row for the
/// entry's day and updating it in place, so callers never create duplicates.
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
  Future<MoodEntry> save(MoodEntry entry) async {
    final db = await _database;
    final now = DateTime.now();
    final normalized = entry.copyWith(date: AppDates.dateOnly(entry.date));

    return db.transaction<MoodEntry>((txn) async {
      final existing = await txn.query(
        table,
        columns: ['id', 'created_at'],
        where: 'date = ?',
        whereArgs: [AppDates.dateKey(normalized.date)],
        limit: 1,
      );

      if (existing.isEmpty) {
        final toInsert = normalized.copyWith(createdAt: now, updatedAt: now);
        final id = await txn.insert(table, toInsert.toMap());
        return toInsert.copyWith(id: id);
      }

      final existingId = existing.first['id']! as int;
      final existingCreatedMs = existing.first['created_at']! as int;
      final updated = normalized.copyWith(
        id: existingId,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          existingCreatedMs,
          isUtc: true,
        ).toLocal(),
        updatedAt: now,
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
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  /// Removes every mood check-in (used by "clear all data").
  Future<void> deleteAll() async {
    final db = await _database;
    await db.delete(table);
  }
}
