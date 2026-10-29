import 'package:flutter_test/flutter_test.dart';
import 'package:moodly/core/database/app_database.dart';
import 'package:moodly/models/emotion.dart';
import 'package:moodly/models/mood.dart';
import 'package:moodly/models/mood_entry.dart';
import 'package:moodly/repositories/mood_repository.dart';

import 'helpers/test_harness.dart';

void main() {
  setupSqfliteFfiForTests();

  group('MoodRepository (in-memory)', () {
    late AppDatabase db;
    late MoodRepository repository;

    setUp(() {
      db = inMemoryDatabase();
      repository = MoodRepository(db);
    });

    tearDown(() async => db.close());

    MoodEntry entry({
      int? id,
      DateTime? date,
      Mood mood = Mood.good,
      int energy = 4,
      String? note,
      List<Emotion> emotions = const [],
    }) => MoodEntry(
      id: id,
      date: date ?? DateTime(2026, 10, 28),
      mood: mood,
      energy: energy,
      note: note,
      emotions: emotions,
    );

    test('save assigns an id and getByDate retrieves it', () async {
      final saved = await repository.save(entry(mood: Mood.great, energy: 5));
      expect(saved.id, isNotNull);

      final fetched = await repository.getByDate(DateTime(2026, 10, 28, 8));
      expect(fetched, isNotNull);
      expect(fetched!.mood, Mood.great);
      expect(fetched.energy, 5);
      expect(fetched.id, saved.id);
    });

    test('enforces one check-in per local calendar day (upsert)', () async {
      final first = await repository.save(
        entry(mood: Mood.low, energy: 2, note: 'rough start'),
      );
      final second = await repository.save(
        entry(mood: Mood.good, energy: 4, note: 'turned around'),
      );

      expect(await repository.count(), 1);
      expect(second.id, first.id);
      // createdAt is preserved (SQLite stores millisecond precision).
      expect(
        second.createdAt.millisecondsSinceEpoch,
        first.createdAt.millisecondsSinceEpoch,
      );

      final stored = await repository.getByDate(DateTime(2026, 10, 28));
      expect(stored!.mood, Mood.good);
      expect(stored.note, 'turned around');
      expect(stored.energy, 4);
    });

    test('different local days create different entries', () async {
      await repository.save(
        entry(date: DateTime(2026, 10, 27), mood: Mood.okay),
      );
      await repository.save(
        entry(date: DateTime(2026, 10, 28), mood: Mood.great),
      );
      expect(await repository.count(), 2);
    });

    test(
      'same wall-clock day with different times is still one entry',
      () async {
        await repository.save(entry(date: DateTime(2026, 10, 28, 0, 5)));
        await repository.save(entry(date: DateTime(2026, 10, 28, 23, 55)));
        expect(await repository.count(), 1);
      },
    );

    test(
      'getAll returns newest first and getInRange filters inclusively',
      () async {
        await repository.save(entry(date: DateTime(2026, 10, 26)));
        await repository.save(entry(date: DateTime(2026, 10, 27)));
        await repository.save(entry(date: DateTime(2026, 10, 28)));

        final all = await repository.getAll();
        expect(all.map((e) => e.date.day), [28, 27, 26]);

        final ranged = await repository.getInRange(
          DateTime(2026, 10, 26),
          DateTime(2026, 10, 27),
        );
        expect(ranged.map((e) => e.date.day), [26, 27]);
      },
    );

    test('delete removes a single entry', () async {
      final saved = await repository.save(entry());
      await repository.delete(saved.id!);
      expect(await repository.count(), 0);
      expect(await repository.getByDate(DateTime(2026, 10, 28)), isNull);
    });

    test('deleteAll clears everything', () async {
      await repository.save(entry(date: DateTime(2026, 10, 27)));
      await repository.save(entry(date: DateTime(2026, 10, 28)));
      await repository.deleteAll();
      expect(await repository.count(), 0);
    });

    test('empty database yields empty results, not errors', () async {
      expect(await repository.getAll(), isEmpty);
      expect(await repository.getByDate(DateTime(2026, 10, 28)), isNull);
      expect(await repository.count(), 0);
    });
  });

  group('MoodRepository persistence (file-backed)', () {
    test('data survives closing and reopening the database', () async {
      final env = fileDatabase();
      addTearDown(env.cleanup);

      final repo1 = MoodRepository(env.database);
      await repo1.save(
        MoodEntry(
          date: DateTime(2026, 10, 28),
          mood: Mood.great,
          energy: 5,
          emotions: const [Emotion.happy],
          note: 'Persisted!',
        ),
      );
      await env.database.close();

      // Reopen the same file with a brand-new repository instance.
      final reopened = reopenDatabaseAt(env.path);
      final repo2 = MoodRepository(reopened.database);

      final fetched = await repo2.getByDate(DateTime(2026, 10, 28));
      expect(fetched, isNotNull);
      expect(fetched!.mood, Mood.great);
      expect(fetched.note, 'Persisted!');
      expect(fetched.emotions, const [Emotion.happy]);
      await reopened.database.close();
    });
  });
}
