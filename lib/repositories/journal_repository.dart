import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import '../models/journal_entry.dart';

/// Data access for standalone journal entries (any number per day).
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

  /// Inserts a new entry and returns it with its assigned id.
  Future<JournalEntry> insert(JournalEntry entry) async {
    final db = await _database;
    final now = DateTime.now();
    final toInsert = entry.copyWith(createdAt: now, updatedAt: now);
    final id = await db.insert(table, toInsert.toMap());
    return toInsert.copyWith(id: id);
  }

  /// Updates an existing entry. Throws if [entry] has no id.
  Future<void> update(JournalEntry entry) async {
    final id = entry.id;
    if (id == null) {
      throw ArgumentError('Cannot update a journal entry without an id');
    }
    final db = await _database;
    await db.update(
      table,
      entry.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(int id) async {
    final db = await _database;
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  /// Removes every journal entry (used by "clear all data").
  Future<void> deleteAll() async {
    final db = await _database;
    await db.delete(table);
  }
}
