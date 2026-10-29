import 'dart:io';

import 'package:moodly/core/database/app_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Initializes sqflite's FFI implementation so real SQLite databases can be
/// created in unit/widget tests on desktop hosts.
void setupSqfliteFfiForTests() {
  sqfliteFfiInit();
}

/// An in-memory database for fast, isolated tests.
AppDatabase inMemoryDatabase() => AppDatabase(
  dbFactory: databaseFactoryFfiNoIsolate,
  dbPath: inMemoryDatabasePath,
);

/// A file-backed database in a temp directory, used to verify persistence
/// across app restarts. Returns the database plus its path and cleanup fn.
({AppDatabase database, String path, void Function() cleanup}) fileDatabase() {
  final dir = Directory.systemTemp.createTempSync('moodly_test_');
  final path = p.join(dir.path, 'moodly_test.db');
  return (
    database: AppDatabase(dbFactory: databaseFactoryFfiNoIsolate, dbPath: path),
    path: path,
    cleanup: () {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {
        // Best-effort cleanup of temp dirs on Windows.
      }
    },
  );
}

/// Opens another connection to an existing database file (simulates an app
/// restart).
({AppDatabase database, void Function() cleanup}) reopenDatabaseAt(
  String path,
) => (
  database: AppDatabase(dbFactory: databaseFactoryFfiNoIsolate, dbPath: path),
  cleanup: () {},
);
