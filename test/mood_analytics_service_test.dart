import 'package:flutter_test/flutter_test.dart';
import 'package:moodly/models/emotion.dart';
import 'package:moodly/models/mood.dart';
import 'package:moodly/models/mood_entry.dart';
import 'package:moodly/services/mood_analytics_service.dart';

void main() {
  final today = DateTime(2026, 10, 28);

  MoodEntry entry(
    DateTime date, {
    Mood mood = Mood.okay,
    int energy = 3,
    List<Emotion> emotions = const [],
  }) => MoodEntry(date: date, mood: mood, energy: energy, emotions: emotions);

  group('MoodAnalyticsService', () {
    test('empty data yields null aggregates', () {
      final service = MoodAnalyticsService();
      final analytics = service.analyzeAll(const []);
      expect(analytics.totalEntries, 0);
      expect(analytics.averageMoodScore, isNull);
      expect(analytics.averageEnergy, isNull);
      expect(analytics.dominantMood, isNull);
      expect(analytics.currentStreak(), 0);
      expect(analytics.longestStreak(), 0);
    });

    test('computes counts, averages and dominant mood', () {
      final service = MoodAnalyticsService();
      final entries = [
        entry(DateTime(2026, 10, 26), mood: Mood.great, energy: 5),
        entry(DateTime(2026, 10, 27), mood: Mood.good, energy: 4),
        entry(DateTime(2026, 10, 28), mood: Mood.okay, energy: 3),
      ];
      final analytics = service.analyzeAll(entries);
      expect(analytics.totalEntries, 3);
      expect(analytics.checkInDays, 3);
      expect(analytics.moodCounts[Mood.great], 1);
      expect(analytics.moodCounts[Mood.okay], 1);
      expect(analytics.dominantMood, Mood.great);
      expect(analytics.averageMoodScore, closeTo(4.0, 0.001));
      expect(analytics.averageEnergy, closeTo(4.0, 0.001));
    });

    test('average energy by mood', () {
      final service = MoodAnalyticsService();
      final entries = [
        entry(DateTime(2026, 10, 26), mood: Mood.great, energy: 5),
        entry(DateTime(2026, 10, 27), mood: Mood.great, energy: 3),
        entry(DateTime(2026, 10, 28), mood: Mood.low, energy: 1),
      ];
      final analytics = service.analyzeAll(entries);
      expect(analytics.averageEnergyByMood[Mood.great], closeTo(4.0, 0.001));
      expect(analytics.averageEnergyByMood[Mood.low], closeTo(1.0, 0.001));
    });

    test('current streak counts consecutive days ending today', () {
      final service = MoodAnalyticsService();
      final entries = [
        entry(DateTime(2026, 10, 26)),
        entry(DateTime(2026, 10, 27)),
        entry(DateTime(2026, 10, 28)),
      ];
      final analytics = service.analyzeAll(entries);
      expect(analytics.currentStreak(today: today), 3);
    });

    test('streak breaks when a day is missing', () {
      final service = MoodAnalyticsService();
      final entries = [
        entry(DateTime(2026, 10, 26)),
        entry(DateTime(2026, 10, 28)),
      ];
      final analytics = service.analyzeAll(entries);
      expect(analytics.currentStreak(today: today), 1);
    });

    test('longest streak across history', () {
      final service = MoodAnalyticsService();
      final entries = [
        entry(DateTime(2026, 10, 20)),
        entry(DateTime(2026, 10, 21)),
        entry(DateTime(2026, 10, 22)),
        entry(DateTime(2026, 10, 26)),
        entry(DateTime(2026, 10, 27)),
        entry(DateTime(2026, 10, 28)),
      ];
      final analytics = service.analyzeAll(entries);
      expect(analytics.longestStreak(), 3);
    });

    test('missing days in range', () {
      final service = MoodAnalyticsService();
      final entries = [
        entry(DateTime(2026, 10, 26)),
        entry(DateTime(2026, 10, 28)),
      ];
      final analytics = service.analyze(
        entries,
        from: DateTime(2026, 10, 26),
        to: DateTime(2026, 10, 28),
      );
      final missing = analytics.missingDaysInRange(
        from: DateTime(2026, 10, 26),
        to: DateTime(2026, 10, 28),
      );
      expect(missing, [DateTime(2026, 10, 27)]);
    });

    test('date filter restricts entries', () {
      final service = MoodAnalyticsService();
      final entries = [
        entry(DateTime(2026, 10, 25)),
        entry(DateTime(2026, 10, 27)),
        entry(DateTime(2026, 10, 29)),
      ];
      final analytics = service.analyze(
        entries,
        from: DateTime(2026, 10, 26),
        to: DateTime(2026, 10, 28),
      );
      expect(analytics.totalEntries, 1);
      expect(analytics.entries.first.date.day, 27);
    });
  });
}
