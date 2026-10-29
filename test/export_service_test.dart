import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodly/core/database/app_database.dart';
import 'package:moodly/models/emotion.dart';
import 'package:moodly/models/mood.dart';
import 'package:moodly/models/mood_entry.dart';
import 'package:moodly/models/journal_entry.dart';
import 'package:moodly/repositories/journal_repository.dart';
import 'package:moodly/repositories/mood_repository.dart';
import 'package:moodly/services/export_service.dart';

import 'helpers/test_harness.dart';

void main() {
  setupSqfliteFfiForTests();

  group('ExportService', () {
    late AppDatabase db;
    late MoodRepository moodRepo;
    late JournalRepository journalRepo;
    late ExportService exportService;

    setUp(() {
      db = inMemoryDatabase();
      moodRepo = MoodRepository(db);
      journalRepo = JournalRepository(db);
      exportService = ExportService(
        moodRepository: moodRepo,
        journalRepository: journalRepo,
      );
    });

    tearDown(() async => db.close());

    test(
      'buildJson produces valid JSON with metadata and empty counts',
      () async {
        final fixedDate = DateTime.utc(2026, 10, 29, 14, 30);
        final raw = await exportService.buildJson(
          moodEntries: const [],
          journalEntries: const [],
          exportedAt: fixedDate,
        );

        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        expect(decoded['app'], 'Moodly');
        expect(decoded['tagline'], 'Your Daily Mood');
        expect(decoded['schemaVersion'], 1);
        expect(decoded['exportedAt'], '2026-10-29T14:30:00.000Z');
        expect(decoded['counts'], {'moodEntries': 0, 'journalEntries': 0});
        expect(decoded['moodEntries'], isEmpty);
        expect(decoded['journalEntries'], isEmpty);
      },
    );

    test(
      'buildJson exports full mood and journal entries with all fields',
      () async {
        final date = DateTime(2026, 10, 29);
        final created = DateTime.utc(2026, 10, 29, 10, 0);

        final mood = MoodEntry(
          id: 1,
          date: date,
          mood: Mood.great,
          emotions: const [Emotion.happy, Emotion.grateful],
          energy: 5,
          note: 'Wonderful morning walk.',
          createdAt: created,
          updatedAt: created,
        );

        final journal = JournalEntry(
          id: 10,
          date: date,
          title: 'Morning Reflections',
          body: 'Writing down some thoughts.',
          createdAt: created,
          updatedAt: created,
        );

        final raw = await exportService.buildJson(
          moodEntries: [mood],
          journalEntries: [journal],
        );

        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        expect(decoded['counts']['moodEntries'], 1);
        expect(decoded['counts']['journalEntries'], 1);

        final exportedMoods = decoded['moodEntries'] as List<dynamic>;
        expect(exportedMoods, hasLength(1));
        final m = exportedMoods.first as Map<String, dynamic>;
        expect(m['id'], 1);
        expect(m['date'], '2026-10-29');
        expect(m['mood'], 'great');
        expect(m['moodLabel'], 'Great');
        expect(m['emotions'], ['happy', 'grateful']);
        expect(m['energy'], 5);
        expect(m['note'], 'Wonderful morning walk.');
        expect(m['createdAt'], isNotEmpty);
        expect(m['updatedAt'], isNotEmpty);

        final exportedJournals = decoded['journalEntries'] as List<dynamic>;
        expect(exportedJournals, hasLength(1));
        final j = exportedJournals.first as Map<String, dynamic>;
        expect(j['id'], 10);
        expect(j['date'], '2026-10-29');
        expect(j['title'], 'Morning Reflections');
        expect(j['body'], 'Writing down some thoughts.');
        expect(j['createdAt'], isNotEmpty);
        expect(j['updatedAt'], isNotEmpty);
      },
    );

    test(
      'buildJson pulls directly from repositories when entries not passed',
      () async {
        await moodRepo.save(
          MoodEntry(
            date: DateTime(2026, 10, 28),
            mood: Mood.good,
            energy: 4,
            emotions: const [Emotion.calm],
          ),
        );

        await journalRepo.insert(
          JournalEntry(
            date: DateTime(2026, 10, 28),
            title: 'Night thoughts',
            body: 'Ready to sleep.',
          ),
        );

        final raw = await exportService.buildJson();
        final decoded = jsonDecode(raw) as Map<String, dynamic>;

        expect(decoded['counts']['moodEntries'], 1);
        expect(decoded['counts']['journalEntries'], 1);
        expect((decoded['moodEntries'] as List).length, 1);
        expect((decoded['journalEntries'] as List).length, 1);
      },
    );
  });
}
