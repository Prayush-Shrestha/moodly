import 'package:moodly/core/database/app_database.dart';
import 'package:moodly/models/journal_reflection.dart';
import 'package:sqflite/sqflite.dart';

/// Data access for generated journal reflections.
///
/// Reflections belong to a journal entry and are removed when that entry is
/// deleted (ON DELETE CASCADE in the schema).
class JournalReflectionRepository {
  JournalReflectionRepository(this._db);

  static const String table = 'journal_reflections';

  final AppDatabase _db;

  Future<Database> get _database => _db.open();

  /// The reflection for a journal entry, if one exists.
  Future<JournalReflection?> getByEntryId(int journalEntryId) async {
    final db = await _database;
    final rows = await db.query(
      table,
      where: 'journal_entry_id = ?',
      whereArgs: [journalEntryId],
      limit: 1,
      orderBy: 'created_at DESC',
    );
    return rows.isEmpty ? null : JournalReflection.fromMap(rows.first);
  }

  /// Inserts a reflection and returns it with its assigned id.
  Future<JournalReflection> insert(JournalReflection reflection) async {
    final db = await _database;
    final id = await db.insert(table, reflection.toMap());
    return reflection.copyWith(id: id);
  }

  /// Replaces the reflection for [journalEntryId] (upsert by entry id).
  Future<JournalReflection> saveForEntry(
    int journalEntryId,
    JournalReflection reflection,
  ) async {
    final existing = await getByEntryId(journalEntryId);
    if (existing != null && existing.id != null) {
      await dbUpdate(
        existing.id!,
        reflection.copyWith(id: existing.id, journalEntryId: journalEntryId),
      );
      return reflection.copyWith(
        id: existing.id,
        journalEntryId: journalEntryId,
      );
    }
    return insert(reflection.copyWith(journalEntryId: journalEntryId));
  }

  Future<void> dbUpdate(int id, JournalReflection reflection) async {
    final db = await _database;
    await db.update(
      table,
      reflection.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Deletes the reflection for a journal entry (called when the entry is
  /// deleted; the schema also cascades deletes).
  Future<void> deleteByEntryId(int journalEntryId) async {
    final db = await _database;
    await db.delete(
      table,
      where: 'journal_entry_id = ?',
      whereArgs: [journalEntryId],
    );
  }

  /// Removes every reflection (used by "clear all data").
  Future<void> deleteAll() async {
    final db = await _database;
    await db.delete(table);
  }
}
