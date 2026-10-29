import 'package:flutter_test/flutter_test.dart';
import 'package:moodly/core/database/app_database.dart';
import 'package:moodly/models/journal_entry.dart';
import 'package:moodly/repositories/journal_repository.dart';

import 'helpers/test_harness.dart';

void main() {
  setupSqfliteFfiForTests();

  group('JournalEntry model', () {
    test('requires a non-empty body', () {
      expect(
        () => JournalEntry(date: DateTime(2026, 10, 28), body: '   '),
        throwsArgumentError,
      );
    });

    test('blank titles become null and map to a display placeholder', () {
      final entry = JournalEntry(
        date: DateTime(2026, 10, 28),
        title: '  ',
        body: 'Hello',
      );
      expect(entry.title, isNull);
      expect(entry.displayTitle, 'Journal entry');
    });

    test('toMap/fromMap round-trips', () {
      final entry = JournalEntry(
        date: DateTime(2026, 10, 28),
        title: 'Reflection',
        body: 'First line\nsecond line.',
      );
      final restored = JournalEntry.fromMap(entry.toMap());
      expect(restored.title, 'Reflection');
      expect(restored.body, 'First line\nsecond line.');
      expect(restored.date, DateTime(2026, 10, 28));
    });

    test('matches performs case-insensitive search on title and body', () {
      final entry = JournalEntry(
        date: DateTime(2026, 10, 28),
        title: 'Gratitude',
        body: 'Felt calm today',
      );
      expect(entry.matches('gratitude'), isTrue);
      expect(entry.matches('CALM'), isTrue);
      expect(entry.matches('rainy'), isFalse);
      expect(entry.matches(''), isTrue);
    });
  });

  group('JournalRepository', () {
    late AppDatabase db;
    late JournalRepository repository;

    setUp(() {
      db = inMemoryDatabase();
      repository = JournalRepository(db);
    });

    tearDown(() async => db.close());

    test(
      'insert assigns an id; multiple entries per day are allowed',
      () async {
        final a = await repository.insert(
          JournalEntry(
            date: DateTime(2026, 10, 28),
            title: 'Morning',
            body: 'Woke early.',
          ),
        );
        final b = await repository.insert(
          JournalEntry(
            date: DateTime(2026, 10, 28),
            title: 'Evening',
            body: 'Long day.',
          ),
        );
        expect(a.id, isNotNull);
        expect(b.id, isNotNull);
        expect(a.id, isNot(b.id));
        expect(await repository.count(), 2);
      },
    );

    test('update persists changes', () async {
      final created = await repository.insert(
        JournalEntry(date: DateTime(2026, 10, 28), body: 'Original text'),
      );
      await repository.update(
        created.copyWith(title: 'Edited', body: 'Updated text'),
      );
      final fetched = await repository.getById(created.id!);
      expect(fetched!.title, 'Edited');
      expect(fetched.body, 'Updated text');
    });

    test('update without an id throws', () {
      expect(
        repository.update(
          JournalEntry(date: DateTime(2026, 10, 28), body: 'x'),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('getAll returns newest first; search filters by query', () async {
      await repository.insert(
        JournalEntry(
          date: DateTime(2026, 10, 26),
          title: 'Rainy day',
          body: 'Walked in the rain.',
        ),
      );
      await repository.insert(
        JournalEntry(
          date: DateTime(2026, 10, 28),
          title: 'Sunny day',
          body: 'Feeling grateful.',
        ),
      );

      final all = await repository.getAll();
      expect(all.first.title, 'Sunny day');

      final searchResults = await repository.getAll(query: 'grateful');
      expect(searchResults, hasLength(1));
      expect(searchResults.first.title, 'Sunny day');

      final noResults = await repository.getAll(query: 'zzz-nothing');
      expect(noResults, isEmpty);
    });

    test('delete removes an entry and deleteAll clears the table', () async {
      final created = await repository.insert(
        JournalEntry(date: DateTime(2026, 10, 28), body: 'Temp'),
      );
      await repository.delete(created.id!);
      expect(await repository.count(), 0);

      await repository.insert(
        JournalEntry(date: DateTime(2026, 10, 28), body: 'A'),
      );
      await repository.insert(
        JournalEntry(date: DateTime(2026, 10, 28), body: 'B'),
      );
      await repository.deleteAll();
      expect(await repository.count(), 0);
    });
  });
}
