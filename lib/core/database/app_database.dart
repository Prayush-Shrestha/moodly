import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../models/client_id.dart';

/// Owns the SQLite connection and schema for Moodly.
///
/// The database is created lazily the first time [open] is awaited. An
/// optional [factory] and [path] can be injected, which keeps unit and widget
/// tests fully local (e.g. sqflite_common_ffi with an in-memory database).
///
/// Storage is **local and not encrypted by default** — the file lives in the
/// platform's databases directory (documented in the README).
class AppDatabase {
  AppDatabase({DatabaseFactory? dbFactory, String? dbPath})
    : _factory = dbFactory ?? databaseFactory,
      _path = dbPath;

  static const String name = 'moodly.db';

  /// v1: Phase 1 tables. v2: `journal_reflections`. v3: Phase 3 sync columns
  /// (`client_id`, `synced_at`), `generated_reports` and the sync tombstones
  /// table. Existing rows are preserved and backfilled by [_upgradeSchema].
  static const int schemaVersion = 3;

  final DatabaseFactory _factory;
  final String? _path;
  Future<Database>? _opening;

  Future<Database> open() => _opening ??= _open();

  Future<Database> _open() async {
    final dbPath = _path ?? p.join(await getDatabasesPath(), name);
    return _factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        // An injected path (tests) must not reuse sqflite's path-keyed
        // single-instance cache — notably ':memory:', which would otherwise
        // hand every test the previous test's database.
        singleInstance: _path == null,
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      ),
    );
  }

  /// Idempotent schema creation. When a fresh database is created at version 3
  /// all tables (including Phase 2 + Phase 3 tables) are created here.
  static Future<void> _createSchema(Database db, int version) async {
    await _createMoodEntriesTable(db);
    await _createJournalEntriesTable(db);
    await _createJournalReflectionsTable(db);
    await _createGeneratedReportsTable(db);
    await _createSyncTombstonesTable(db);
  }

  /// Versioned migration. Existing mood/journal rows keep their data; new
  /// sync columns are added and backfilled with stable generated client ids
  /// (so rows synced for the first time are recognized afterwards).
  static Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2 && newVersion >= 2) {
      await _createJournalReflectionsTable(db);
    }
    if (oldVersion < 3 && newVersion >= 3) {
      await _addSyncColumns(db, 'mood_entries');
      await _addSyncColumns(db, 'journal_entries');
      await _addReflectionColumns(db);
      await _createGeneratedReportsTable(db);
      await _createSyncTombstonesTable(db);
    }
  }

  /// Phase 3 columns for AI reflections. Existing rows get neutral defaults
  /// (they were produced by the local rule-based service).
  static Future<void> _addReflectionColumns(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(journal_reflections)');
    final names = columns.map((c) => c['name'] as String).toSet();
    const additions = {
      'positive_observations': "TEXT NOT NULL DEFAULT ''",
      'challenges': "TEXT NOT NULL DEFAULT ''",
      'explicit_emotions': "TEXT NOT NULL DEFAULT ''",
      'inferred_emotions': "TEXT NOT NULL DEFAULT ''",
      'provider': "TEXT NOT NULL DEFAULT 'local_rules'",
    };
    for (final entry in additions.entries) {
      if (!names.contains(entry.key)) {
        await db.execute(
          'ALTER TABLE journal_reflections ADD COLUMN '
          '${entry.key} ${entry.value}',
        );
      }
    }
  }

  static Future<void> _addSyncColumns(Database db, String table) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final names = columns.map((c) => c['name'] as String).toSet();
    if (!names.contains('client_id')) {
      await db.execute("ALTER TABLE $table ADD COLUMN client_id TEXT");
    }
    if (!names.contains('synced_at')) {
      await db.execute('ALTER TABLE $table ADD COLUMN synced_at INTEGER');
    }
    // Backfill stable ids for pre-existing rows (idempotent).
    final rows = await db.query(table, columns: ['id', 'client_id']);
    for (final row in rows) {
      if (row['client_id'] == null) {
        await db.update(
          table,
          {'client_id': ClientId.generate()},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }
  }

  static Future<void> _createMoodEntriesTable(Database db) async {
    await db.execute('''
      CREATE TABLE mood_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL UNIQUE,
        mood TEXT NOT NULL,
        emotions TEXT NOT NULL DEFAULT '',
        energy INTEGER NOT NULL,
        note TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        client_id TEXT,
        synced_at INTEGER
      )
    ''');
  }

  static Future<void> _createJournalEntriesTable(Database db) async {
    await db.execute('''
      CREATE TABLE journal_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        title TEXT,
        body TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        client_id TEXT,
        synced_at INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_journal_entries_date ON journal_entries (date DESC)',
    );
  }

  static Future<void> _createJournalReflectionsTable(Database db) async {
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
        positive_observations TEXT NOT NULL DEFAULT '',
        challenges TEXT NOT NULL DEFAULT '',
        explicit_emotions TEXT NOT NULL DEFAULT '',
        inferred_emotions TEXT NOT NULL DEFAULT '',
        provider TEXT NOT NULL DEFAULT 'local_rules',
        FOREIGN KEY (journal_entry_id) REFERENCES journal_entries(id)
          ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_journal_reflections_entry_id ON journal_reflections '
      '(journal_entry_id)',
    );
  }

  /// Reports the user generated and saved locally (viewable offline).
  static Future<void> _createGeneratedReportsTable(Database db) async {
    await db.execute('''
      CREATE TABLE generated_reports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        period_start TEXT NOT NULL,
        period_end TEXT NOT NULL,
        period_label TEXT NOT NULL,
        data TEXT NOT NULL,
        narrative_source TEXT NOT NULL DEFAULT 'local_rules',
        created_at INTEGER NOT NULL,
        UNIQUE(kind, period_start)
      )
    ''');
  }

  /// Tombstones for locally deleted rows that still need to reach the cloud.
  static Future<void> _createSyncTombstonesTable(Database db) async {
    await db.execute('''
      CREATE TABLE sync_tombstones (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        client_id TEXT NOT NULL,
        deleted_at INTEGER NOT NULL,
        UNIQUE(kind, client_id)
      )
    ''');
  }

  Future<void> close() async {
    final pending = _opening;
    _opening = null;
    if (pending != null) {
      final db = await pending;
      await db.close();
    }
  }
}

/// Turns low-level database errors into short, user-friendly messages.
String describeDbError(Object error) {
  if (error is DatabaseException) {
    return 'A database error occurred. Your existing data is safe — please try again.';
  }
  return 'Something went wrong while saving. Please try again.';
}
