import 'package:flutter_test/flutter_test.dart';
import 'package:moodly/core/database/app_database.dart';
import 'package:moodly/models/journal_entry.dart';
import 'package:moodly/models/journal_reflection.dart';
import 'package:moodly/repositories/journal_reflection_repository.dart';
import 'package:moodly/repositories/journal_repository.dart';

import 'helpers/test_harness.dart';

void main() {
  setupSqfliteFfiForTests();

  group('JournalReflectionRepository (in-memory)', () {
    late AppDatabase db;
    late JournalReflectionRepository reflectionRepo;
    late JournalRepository journalRepo;

    setUp(() {
      db = inMemoryDatabase();
      reflectionRepo = JournalReflectionRepository(db);
      journalRepo = JournalRepository(db);
    });

    tearDown(() async => db.close());

    Future<int> createEntry() async {
      final entry = await journalRepo.insert(
        JournalEntry(date: DateTime(2026, 10, 28), body: 'Entry body.'),
      );
      return entry.id!;
    }

    JournalReflection reflection({
      int? id,
      required int journalEntryId,
      String summary = 'A reflection.',
    }) => JournalReflection(
      id: id,
      journalEntryId: journalEntryId,
      summary: summary,
      detectedEmotions: const ['happy'],
      themes: const ['positive'],
      reflectionQuestions: const ['What helped?'],
      isRuleBased: true,
      createdAt: DateTime(2026, 10, 28, 10, 0),
    );

    test('insert assigns an id and getByEntryId retrieves it', () async {
      final entryId = await createEntry();
      final saved = await reflectionRepo.insert(
        reflection(journalEntryId: entryId),
      );
      expect(saved.id, isNotNull);

      final fetched = await reflectionRepo.getByEntryId(entryId);
      expect(fetched, isNotNull);
      expect(fetched!.summary, 'A reflection.');
      expect(fetched.detectedEmotions, const ['happy']);
      expect(fetched.isRuleBased, isTrue);
    });

    test('saveForEntry updates an existing reflection in place', () async {
      final entryId = await createEntry();
      final first = await reflectionRepo.insert(
        reflection(journalEntryId: entryId),
      );
      final second = await reflectionRepo.saveForEntry(
        entryId,
        reflection(journalEntryId: entryId, summary: 'Updated.'),
      );
      expect(second.id, first.id);
      expect((await reflectionRepo.getByEntryId(entryId))!.summary, 'Updated.');
    });

    test('deleteByEntryId removes the reflection', () async {
      final entryId = await createEntry();
      await reflectionRepo.insert(reflection(journalEntryId: entryId));
      await reflectionRepo.deleteByEntryId(entryId);
      expect(await reflectionRepo.getByEntryId(entryId), isNull);
    });

    test('deleteAll clears reflections', () async {
      final a = await createEntry();
      final b = await createEntry();
      await reflectionRepo.insert(reflection(journalEntryId: a));
      await reflectionRepo.insert(reflection(journalEntryId: b));
      await reflectionRepo.deleteAll();
      expect(await reflectionRepo.getByEntryId(a), isNull);
      expect(await reflectionRepo.getByEntryId(b), isNull);
    });

    test('empty database returns null, not an error', () async {
      expect(await reflectionRepo.getByEntryId(1), isNull);
    });
  });

  group('JournalReflectionRepository persistence (file-backed)', () {
    test('reflection survives closing and reopening the database', () async {
      final env = fileDatabase();
      addTearDown(env.cleanup);

      final journalRepo = JournalRepository(env.database);
      final repo1 = JournalReflectionRepository(env.database);
      final entry = await journalRepo.insert(
        JournalEntry(date: DateTime(2026, 10, 28), body: 'Persist me.'),
      );
      await repo1.insert(
        JournalReflection(
          journalEntryId: entry.id!,
          summary: 'Persisted reflection.',
          createdAt: DateTime(2026, 10, 28, 9, 0),
        ),
      );
      await env.database.close();

      final reopened = reopenDatabaseAt(env.path);
      final repo2 = JournalReflectionRepository(reopened.database);
      final fetched = await repo2.getByEntryId(entry.id!);
      expect(fetched, isNotNull);
      expect(fetched!.summary, 'Persisted reflection.');
      await reopened.database.close();
    });
  });
}
