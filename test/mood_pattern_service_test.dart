import 'package:flutter_test/flutter_test.dart';
import 'package:moodly/models/emotion.dart';
import 'package:moodly/models/mood.dart';
import 'package:moodly/models/mood_entry.dart';
import 'package:moodly/services/mood_analytics_service.dart';
import 'package:moodly/services/mood_pattern_service.dart';

void main() {
  final today = DateTime(2026, 10, 28);

  MoodEntry entry(
    DateTime date, {
    Mood mood = Mood.okay,
    int energy = 3,
    List<Emotion> emotions = const [],
  }) => MoodEntry(date: date, mood: mood, energy: energy, emotions: emotions);

  group('MoodPatternService', () {
    test('empty data produces no patterns', () {
      final service = MoodPatternService();
      final analytics = MoodAnalyticsService().analyzeAll(const []);
      final patterns = service.detectPatterns(
        analytics,
        const [],
        today: today,
      );
      expect(patterns, isEmpty);
    });

    test('reports consistency when checking in most days', () {
      final service = MoodPatternService();
      final entries = [
        entry(DateTime(2026, 10, 22)),
        entry(DateTime(2026, 10, 23)),
        entry(DateTime(2026, 10, 24)),
        entry(DateTime(2026, 10, 25)),
        entry(DateTime(2026, 10, 26)),
        entry(DateTime(2026, 10, 27)),
        entry(DateTime(2026, 10, 28)),
      ];
      final analytics = MoodAnalyticsService().analyzeAll(entries);
      final patterns = service.detectPatterns(analytics, entries, today: today);
      expect(patterns.any((p) => p.title.contains('consistently')), isTrue);
    });

    test('reports dominant mood', () {
      final service = MoodPatternService();
      final entries = [
        entry(DateTime(2026, 10, 26), mood: Mood.great),
        entry(DateTime(2026, 10, 27), mood: Mood.great),
        entry(DateTime(2026, 10, 28), mood: Mood.low),
      ];
      final analytics = MoodAnalyticsService().analyzeAll(entries);
      final patterns = service.detectPatterns(analytics, entries, today: today);
      expect(
        patterns.any((p) => p.title.contains('most frequent mood')),
        isTrue,
      );
    });

    test('reports energy-motivation link when significant', () {
      final service = MoodPatternService();
      final entries = [
        entry(
          DateTime(2026, 10, 26),
          mood: Mood.great,
          energy: 5,
          emotions: const [Emotion.motivated],
        ),
        entry(
          DateTime(2026, 10, 27),
          mood: Mood.great,
          energy: 5,
          emotions: const [Emotion.motivated],
        ),
        entry(DateTime(2026, 10, 28), mood: Mood.low, energy: 1),
        entry(DateTime(2026, 10, 29), mood: Mood.low, energy: 2),
      ];
      final analytics = MoodAnalyticsService().analyzeAll(entries);
      final patterns = service.detectPatterns(analytics, entries, today: today);
      expect(
        patterns.any((p) => p.title.contains('Energy and motivation')),
        isTrue,
      );
    });

    test('reports tense emotions when frequent', () {
      final service = MoodPatternService();
      final entries = [
        entry(DateTime(2026, 10, 26), emotions: const [Emotion.stressed]),
        entry(DateTime(2026, 10, 27), emotions: const [Emotion.anxious]),
        entry(DateTime(2026, 10, 28)),
      ];
      final analytics = MoodAnalyticsService().analyzeAll(entries);
      final patterns = service.detectPatterns(analytics, entries, today: today);
      expect(patterns.any((p) => p.title.contains('Tense emotions')), isTrue);
    });

    test('reports current streak when 3+ days', () {
      final service = MoodPatternService();
      final entries = [
        entry(DateTime(2026, 10, 26)),
        entry(DateTime(2026, 10, 27)),
        entry(DateTime(2026, 10, 28)),
      ];
      final analytics = MoodAnalyticsService().analyzeAll(entries);
      final patterns = service.detectPatterns(analytics, entries, today: today);
      expect(patterns.any((p) => p.title.contains('streak')), isTrue);
    });
  });
}
