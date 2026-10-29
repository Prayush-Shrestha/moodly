import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

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
  static const int schemaVersion = 1;

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
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      ),
    );
  }

  /// Idempotent schema creation. Future schema changes go through [onUpgrade]
  /// below with sequential, versioned migrations.
  static Future<void> _createSchema(Database db, int version) async {
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
    await db.execute(
      'CREATE INDEX idx_journal_entries_date ON journal_entries (date DESC)',
    );
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
