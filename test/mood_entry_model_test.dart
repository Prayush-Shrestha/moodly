import 'package:flutter_test/flutter_test.dart';
import 'package:moodly/core/utils/date_utils.dart';
import 'package:moodly/models/emotion.dart';
import 'package:moodly/models/mood.dart';
import 'package:moodly/models/mood_entry.dart';

void main() {
  group('Mood', () {
    test('fromStorageName resolves known names and falls back for unknown', () {
      expect(Mood.fromStorageName('great'), Mood.great);
      expect(Mood.fromStorageName('terrible'), Mood.terrible);
      expect(Mood.fromStorageName('something-new'), Mood.okay);
      expect(Mood.fromStorageName(null), Mood.okay);
    });

    test('scores are ordered from terrible (1) to great (5)', () {
      expect(Mood.terrible.score, 1);
      expect(Mood.low.score, 2);
      expect(Mood.okay.score, 3);
      expect(Mood.good.score, 4);
      expect(Mood.great.score, 5);
    });
  });

  group('Emotion serialization', () {
    test('round-trips through the storage format', () {
      const emotions = [Emotion.calm, Emotion.anxious, Emotion.grateful];
      final stored = serializeEmotions(emotions);
      expect(stored, 'calm,anxious,grateful');
      expect(parseEmotions(stored), emotions);
    });

    test('tolerates empty and unknown values', () {
      expect(parseEmotions(null), isEmpty);
      expect(parseEmotions(''), isEmpty);
      expect(parseEmotions('calm,not-a-real-emotion'), [Emotion.calm]);
    });
  });

  group('MoodEntry', () {
    final createdAt = DateTime(2026, 10, 28, 9, 30);

    MoodEntry buildEntry() => MoodEntry(
      date: DateTime(2026, 10, 28, 23, 15),
      mood: Mood.good,
      emotions: const [Emotion.calm, Emotion.tired],
      energy: 4,
      note: 'Solid day of work.',
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    test('normalizes date to the local calendar day', () {
      expect(buildEntry().date, DateTime(2026, 10, 28));
      expect(buildEntry().date.hour, 0);
    });

    test('toMap/fromMap round-trips all fields', () {
      final entry = buildEntry();
      final restored = MoodEntry.fromMap(entry.toMap());
      expect(restored.id, entry.id);
      expect(restored.date, entry.date);
      expect(restored.mood, Mood.good);
      expect(restored.emotions, const [Emotion.calm, Emotion.tired]);
      expect(restored.energy, 4);
      expect(restored.note, 'Solid day of work.');
      expect(restored.createdAt, entry.createdAt);
      expect(restored.updatedAt, entry.updatedAt);
    });

    test('toJson/fromJson round-trips all fields', () {
      final entry = buildEntry().copyWith(id: 7);
      final restored = MoodEntry.fromJson(entry.toJson());
      expect(restored.id, 7);
      expect(restored.date, entry.date);
      expect(restored.mood, Mood.good);
      expect(restored.emotions, const [Emotion.calm, Emotion.tired]);
      expect(restored.energy, 4);
      expect(restored.note, 'Solid day of work.');
    });

    test('notes are optional', () {
      final entry = MoodEntry(
        date: DateTime(2026, 10, 28),
        mood: Mood.great,
        energy: 5,
      );
      expect(entry.note, isNull);
      expect(MoodEntry.fromMap(entry.toMap()).note, isNull);
    });

    test('energy must be within 1-5', () {
      expect(
        () =>
            MoodEntry(date: DateTime(2026, 10, 28), mood: Mood.okay, energy: 0),
        throwsArgumentError,
      );
      expect(
        () =>
            MoodEntry(date: DateTime(2026, 10, 28), mood: Mood.okay, energy: 6),
        throwsArgumentError,
      );
      expect(
        () =>
            MoodEntry(date: DateTime(2026, 10, 28), mood: Mood.okay, energy: 1),
        returnsNormally,
      );
      expect(
        () =>
            MoodEntry(date: DateTime(2026, 10, 28), mood: Mood.okay, energy: 5),
        returnsNormally,
      );
    });

    test('copyWith clearNote removes the note', () {
      final entry = buildEntry().copyWith(note: '', clearNote: true);
      expect(entry.note, isNull);
    });
  });

  group('AppDates', () {
    test('dateKey formats with zero padding and parses back', () {
      final date = DateTime(2026, 3, 5, 18, 42);
      expect(AppDates.dateKey(date), '2026-03-05');
      expect(AppDates.parseDateKey('2026-03-05'), DateTime(2026, 3, 5));
    });

    test('isSameDay ignores time of day', () {
      expect(
        AppDates.isSameDay(
          DateTime(2026, 10, 28, 1),
          DateTime(2026, 10, 28, 23),
        ),
        isTrue,
      );
      expect(
        AppDates.isSameDay(DateTime(2026, 10, 28), DateTime(2026, 10, 29)),
        isFalse,
      );
    });

    test('isFuture only flags later local days', () {
      final now = DateTime(2026, 10, 28, 10);
      expect(AppDates.isFuture(DateTime(2026, 10, 29), now: now), isTrue);
      expect(AppDates.isFuture(DateTime(2026, 10, 28, 23), now: now), isFalse);
    });
  });
}
