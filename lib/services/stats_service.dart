import '../models/emotion.dart';
import '../models/mood.dart';
import '../models/mood_entry.dart';

/// Which slice of data to analyze on the Insights screen.
enum StatsPeriod {
  /// Current calendar week (Monday–Sunday, starting today's week).
  week,

  /// Current calendar month.
  month,

  /// Everything recorded so far.
  allTime,
}

/// Direction of the recent-mood comparison.
enum TrendDirection { improving, steady, declining, unknown }

/// Result of comparing the most recent 7 local days with the 7 before them.
class MoodTrend {
  const MoodTrend({
    required this.direction,
    required this.currentAverage,
    required this.previousAverage,
    required this.currentDays,
    required this.previousDays,
  });

  final TrendDirection direction;
  final double? currentAverage;
  final double? previousAverage;
  final int currentDays;
  final int previousDays;

  static const MoodTrend empty = MoodTrend(
    direction: TrendDirection.unknown,
    currentAverage: null,
    previousAverage: null,
    currentDays: 0,
    previousDays: 0,
  );
}

/// All analytics computed from real saved entries. Nothing is fabricated:
/// nullable aggregates stay `null` when there is no underlying data.
class MoodStats {
  const MoodStats({
    required this.period,
    required this.entries,
    required this.trend,
  });

  final StatsPeriod period;

  /// Entries inside the selected period, oldest first.
  final List<MoodEntry> entries;

  /// Last-7-days vs previous-7-days comparison (always computed from all data).
  final MoodTrend trend;

  int get totalEntries => entries.length;

  int get checkInDays => entries.length;

  /// Number of distinct local days with at least one entry in range.
  Map<Mood, int> get moodCounts {
    final counts = <Mood, int>{for (final mood in Mood.values) mood: 0};
    for (final entry in entries) {
      counts[entry.mood] = (counts[entry.mood] ?? 0) + 1;
    }
    return counts;
  }

  Map<Emotion, int> get emotionCounts {
    final counts = <Emotion, int>{};
    for (final entry in entries) {
      for (final emotion in entry.emotions) {
        counts[emotion] = (counts[emotion] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// Emotions ranked by frequency (ties keep enum order), most frequent first.
  List<MapEntry<Emotion, int>> get topEmotions {
    final entries = emotionCounts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.index.compareTo(b.key.index);
      });
    return entries;
  }

  /// Mean mood score (1–5), or `null` when there are no entries.
  double? get averageMoodScore {
    if (entries.isEmpty) return null;
    final total = entries.fold<int>(0, (sum, e) => sum + e.mood.score);
    return total / entries.length;
  }

  /// Mean energy (1–5), or `null` when there are no entries.
  double? get averageEnergy {
    if (entries.isEmpty) return null;
    final total = entries.fold<int>(0, (sum, e) => sum + e.energy);
    return total / entries.length;
  }

  /// The mood most often recorded in this period, or `null`.
  Mood? get dominantMood {
    Mood? best;
    var bestCount = 0;
    for (final entry in moodCounts.entries) {
      if (entry.value > bestCount) {
        bestCount = entry.value;
        best = entry.key;
      }
    }
    return bestCount == 0 ? null : best;
  }
}

/// Pure analytics functions over saved [MoodEntry] lists.
///
/// Kept free of Flutter/SQLite dependencies so it is trivially unit-testable.
abstract final class StatsService {
  /// Filters [entries] to [period] relative to [today] (local days).
  ///
  /// - week: the current calendar week, Monday through today
  /// - month: the current calendar month, 1st through today
  /// - allTime: everything
  static List<MoodEntry> filterPeriod(
    List<MoodEntry> entries,
    StatsPeriod period, {
    DateTime? today,
  }) {
    final now = today ?? DateTime.now();
    switch (period) {
      case StatsPeriod.week:
        final start = _startOfWeek(now);
        return entries
            .where((e) => !e.date.isBefore(start) && !e.date.isAfter(now))
            .toList();
      case StatsPeriod.month:
        final start = DateTime(now.year, now.month);
        return entries
            .where((e) => !e.date.isBefore(start) && !e.date.isAfter(now))
            .toList();
      case StatsPeriod.allTime:
        return List<MoodEntry>.of(entries);
    }
  }

  /// Computes stats for [entries] already filtered to the desired period.
  /// [allEntries] (unfiltered) is used for the trend comparison.
  static MoodStats compute({
    required List<MoodEntry> entries,
    required StatsPeriod period,
    List<MoodEntry>? allEntries,
    DateTime? today,
  }) {
    final sorted = List<MoodEntry>.of(entries)
      ..sort((a, b) => a.date.compareTo(b.date));
    return MoodStats(
      period: period,
      entries: sorted,
      trend: computeTrend(allEntries ?? entries, today: today),
    );
  }

  /// Compares the average mood score of the last 7 local days (including
  /// [today]) against the 7 days before that. Returns [MoodTrend.empty] when
  /// there is not enough data to compare.
  static MoodTrend computeTrend(List<MoodEntry> entries, {DateTime? today}) {
    final now = today ?? DateTime.now();
    final currentStart = _dateOnly(now).subtract(const Duration(days: 6));
    final previousStart = currentStart.subtract(const Duration(days: 7));

    final current = entries.where(
      (e) => !e.date.isBefore(currentStart) && !e.date.isAfter(now),
    );
    final previous = entries
        .where(
          (e) =>
              !e.date.isBefore(previousStart) && e.date.isBefore(currentStart),
        )
        .toList();

    final currentAvg = _averageScore(current);
    final previousAvg = _averageScore(previous);

    if (currentAvg == null || previousAvg == null) {
      return MoodTrend(
        direction: TrendDirection.unknown,
        currentAverage: currentAvg,
        previousAverage: previousAvg,
        currentDays: current.length,
        previousDays: previous.length,
      );
    }

    // A shift smaller than half a mood step counts as steady.
    final delta = currentAvg - previousAvg;
    final direction = delta > 0.49
        ? TrendDirection.improving
        : delta < -0.49
        ? TrendDirection.declining
        : TrendDirection.steady;

    return MoodTrend(
      direction: direction,
      currentAverage: currentAvg,
      previousAverage: previousAvg,
      currentDays: current.length,
      previousDays: previous.length,
    );
  }

  /// Daily average mood scores for the last [days] local days (oldest first).
  /// Only days with a check-in are included — no gaps are invented.
  static List<MapEntry<DateTime, double>> dailyScores(
    List<MoodEntry> entries, {
    int days = 14,
    DateTime? today,
  }) {
    final now = _dateOnly(today ?? DateTime.now());
    final start = now.subtract(Duration(days: days - 1));
    final byDay = <DateTime, List<int>>{};
    for (final entry in entries) {
      if (entry.date.isBefore(start) || entry.date.isAfter(now)) continue;
      byDay.putIfAbsent(_dateOnly(entry.date), () => []).add(entry.mood.score);
    }
    final result = byDay.entries.map((e) {
      final avg = e.value.reduce((a, b) => a + b) / e.value.length;
      return MapEntry(e.key, avg);
    }).toList()..sort((a, b) => a.key.compareTo(b.key));
    return result;
  }

  static double? _averageScore(Iterable<MoodEntry> entries) {
    final list = entries.toList();
    if (list.isEmpty) return null;
    final total = list.fold<int>(0, (sum, e) => sum + e.mood.score);
    return total / list.length;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _startOfWeek(DateTime d) {
    final day = _dateOnly(d);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }
}
