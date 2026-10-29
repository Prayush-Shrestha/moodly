import 'package:flutter_test/flutter_test.dart';
import 'package:moodly/models/emotion.dart';
import 'package:moodly/models/mood.dart';
import 'package:moodly/models/mood_entry.dart';
import 'package:moodly/services/stats_service.dart';

void main() {
  // Wednesday, October 28, 2026 (week starts Monday the 26th).
  final today = DateTime(2026, 10, 28);

  MoodEntry entry(
    DateTime date,
    Mood mood, {
    int energy = 3,
    List<Emotion> emotions = const [],
  }) => MoodEntry(date: date, mood: mood, energy: energy, emotions: emotions);

  group('StatsService.filterPeriod', () {
    final entries = [
      entry(DateTime(2026, 9, 30), Mood.good),
      entry(DateTime(2026, 10, 1), Mood.good),
      entry(DateTime(2026, 10, 26), Mood.great),
      entry(DateTime(2026, 10, 27), Mood.low),
      entry(DateTime(2026, 10, 28), Mood.okay),
    ];

    test('week covers Monday through today', () {
      final week = StatsService.filterPeriod(
        entries,
        StatsPeriod.week,
        today: today,
      );
      expect(week.map((e) => e.date.day), [26, 27, 28]);
    });

    test('month covers the current calendar month', () {
      final month = StatsService.filterPeriod(
        entries,
        StatsPeriod.month,
        today: today,
      );
      expect(month.map((e) => e.date.day), [1, 26, 27, 28]);
    });

    test('allTime keeps everything', () {
      final all = StatsService.filterPeriod(
        entries,
        StatsPeriod.allTime,
        today: today,
      );
      expect(all, hasLength(5));
    });
  });

  group('StatsService.compute', () {
    test('empty data produces empty-but-valid stats', () {
      final stats = StatsService.compute(
        entries: const [],
        period: StatsPeriod.week,
        allEntries: const [],
        today: today,
      );
      expect(stats.totalEntries, 0);
      expect(stats.averageMoodScore, isNull);
      expect(stats.averageEnergy, isNull);
      expect(stats.dominantMood, isNull);
      expect(stats.topEmotions, isEmpty);
      expect(stats.moodCounts.values.every((c) => c == 0), isTrue);
      expect(stats.trend.direction, TrendDirection.unknown);
    });

    test('computes counts, averages and dominant mood from real entries', () {
      final entries = [
        entry(
          DateTime(2026, 10, 26),
          Mood.great,
          energy: 5,
          emotions: const [Emotion.happy, Emotion.calm],
        ),
        entry(
          DateTime(2026, 10, 27),
          Mood.good,
          energy: 4,
          emotions: const [Emotion.happy],
        ),
        entry(
          DateTime(2026, 10, 28),
          Mood.okay,
          energy: 3,
          emotions: const [Emotion.tired],
        ),
      ];
      final stats = StatsService.compute(
        entries: entries,
        period: StatsPeriod.week,
        allEntries: entries,
        today: today,
      );

      expect(stats.totalEntries, 3);
      expect(stats.moodCounts[Mood.great], 1);
      expect(stats.moodCounts[Mood.good], 1);
      expect(stats.moodCounts[Mood.okay], 1);
      expect(stats.moodCounts[Mood.low], 0);
      expect(stats.averageMoodScore, closeTo(4.0, 0.001));
      expect(stats.averageEnergy, closeTo(4.0, 0.001));
      expect(stats.dominantMood, Mood.great);
    });

    test('ranks emotions by frequency with enum order as tiebreak', () {
      final entries = [
        entry(
          DateTime(2026, 10, 26),
          Mood.great,
          emotions: const [Emotion.happy, Emotion.calm],
        ),
        entry(
          DateTime(2026, 10, 27),
          Mood.good,
          emotions: const [Emotion.happy],
        ),
        entry(
          DateTime(2026, 10, 28),
          Mood.okay,
          emotions: const [Emotion.tired],
        ),
      ];
      final stats = StatsService.compute(
        entries: entries,
        period: StatsPeriod.week,
        allEntries: entries,
        today: today,
      );
      final top = stats.topEmotions;
      expect(top.first.key, Emotion.happy);
      expect(top.first.value, 2);
      expect(top.map((e) => e.key), [
        Emotion.happy,
        Emotion.calm,
        Emotion.tired,
      ]);
    });

    test('average energy respects the 1-5 bounds', () {
      final entries = [
        entry(DateTime(2026, 10, 27), Mood.okay, energy: 1),
        entry(DateTime(2026, 10, 28), Mood.okay, energy: 5),
      ];
      final stats = StatsService.compute(
        entries: entries,
        period: StatsPeriod.week,
        allEntries: entries,
        today: today,
      );
      expect(stats.averageEnergy, closeTo(3.0, 0.001));
    });
  });

  group('StatsService.computeTrend', () {
    test('is unknown without data in both windows', () {
      final trend = StatsService.computeTrend(const [], today: today);
      expect(trend.direction, TrendDirection.unknown);
    });

    test('detects improvement when recent scores rise', () {
      final entries = [
        entry(DateTime(2026, 10, 20), Mood.terrible),
        entry(DateTime(2026, 10, 21), Mood.terrible),
        entry(DateTime(2026, 10, 26), Mood.great),
        entry(DateTime(2026, 10, 28), Mood.great),
      ];
      final trend = StatsService.computeTrend(entries, today: today);
      expect(trend.direction, TrendDirection.improving);
      expect(trend.previousAverage, closeTo(1.0, 0.001));
      expect(trend.currentAverage, closeTo(5.0, 0.001));
    });

    test('detects decline and steadiness', () {
      final declining = StatsService.computeTrend([
        entry(DateTime(2026, 10, 20), Mood.great),
        entry(DateTime(2026, 10, 27), Mood.low),
      ], today: today);
      expect(declining.direction, TrendDirection.declining);

      final steady = StatsService.computeTrend([
        entry(DateTime(2026, 10, 20), Mood.okay),
        entry(DateTime(2026, 10, 27), Mood.okay),
      ], today: today);
      expect(steady.direction, TrendDirection.steady);
    });

    test('is unknown when only the recent window has data', () {
      final trend = StatsService.computeTrend([
        entry(DateTime(2026, 10, 27), Mood.good),
      ], today: today);
      expect(trend.direction, TrendDirection.unknown);
      expect(trend.currentAverage, isNotNull);
      expect(trend.previousAverage, isNull);
    });
  });

  group('StatsService.dailyScores', () {
    test(
      'returns only real days, oldest first, averaging same-day entries',
      () {
        final entries = [
          entry(DateTime(2026, 10, 1), Mood.great), // outside the window
          entry(DateTime(2026, 10, 26), Mood.great),
          entry(DateTime(2026, 10, 27), Mood.low),
          entry(DateTime(2026, 10, 27), Mood.good), // same day → averaged
          entry(DateTime(2026, 10, 28), Mood.okay),
        ];
        final daily = StatsService.dailyScores(entries, days: 3, today: today);
        expect(daily.length, 3);
        expect(daily[0].key, DateTime(2026, 10, 26));
        expect(daily[0].value, closeTo(5.0, 0.001));
        expect(daily[1].value, closeTo(3.0, 0.001)); // (2 + 4) / 2
        expect(daily[2].value, closeTo(3.0, 0.001));
      },
    );

    test('is empty when there is no data', () {
      expect(StatsService.dailyScores(const [], today: today), isEmpty);
    });
  });
}
