import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import '../core/utils/date_utils.dart';
import '../models/report.dart';

/// Data access for saved mood reports (Phase 3). One report per
/// (kind, periodStart) — regenerating replaces the stored copy.
class ReportRepository {
  ReportRepository(this._db);

  static const String table = 'generated_reports';

  final AppDatabase _db;

  Future<Database> get _database => _db.open();

  Future<MoodReport?> getForPeriod(String kind, DateTime periodStart) async {
    final db = await _database;
    final rows = await db.query(
      table,
      where: 'kind = ? AND period_start = ?',
      whereArgs: [kind, AppDates.dateKey(periodStart)],
      limit: 1,
    );
    return rows.isEmpty ? null : MoodReport.fromMap(rows.first);
  }

  /// Saves a report, replacing any existing one for the same period.
  Future<MoodReport> save(MoodReport report) async {
    final db = await _database;
    return db.transaction<MoodReport>((txn) async {
      final existing = await txn.query(
        table,
        columns: ['id'],
        where: 'kind = ? AND period_start = ?',
        whereArgs: [report.kind, AppDates.dateKey(report.periodStart)],
        limit: 1,
      );
      if (existing.isEmpty) {
        final id = await txn.insert(table, report.toMap());
        return report.copyWith(id: id);
      }
      final id = existing.first['id']! as int;
      await txn.update(
        table,
        report.toMap()..['id'] = id,
        where: 'id = ?',
        whereArgs: [id],
      );
      return report.copyWith(id: id);
    });
  }

  /// All saved reports, newest first.
  Future<List<MoodReport>> getAll() async {
    final db = await _database;
    final rows = await db.query(table, orderBy: 'period_end DESC, id DESC');
    return rows.map(MoodReport.fromMap).toList();
  }

  Future<void> delete(int id) async {
    final db = await _database;
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAll() async {
    final db = await _database;
    await db.delete(table);
  }
}
