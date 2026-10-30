import 'package:moodly/core/utils/date_utils.dart';
import 'package:moodly/models/emotion.dart';
import 'package:moodly/models/mood.dart';
import 'package:moodly/models/mood_entry.dart';

/// Aggregated analytics over a set of [MoodEntry] records.
///
/// All calculations are explainable, rule-based statistics over real stored
/// data. Nullable aggregates stay `null` when there is no underlying data.
class MoodAnalytics {
  const MoodAnalytics({required this.entries, this.rangeStart, this.rangeEnd});

  /// Entries inside the requested range, oldest first.
  final List<MoodEntry> entries;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;

  int get totalEntries => entries.length;

  /// Distinct local days with at least one entry.
  int get checkInDays {
    final days = <String>{};
    for (final e in entries) {
      days.add(AppDates.dateKey(e.date));
    }
    return days.length;
  }

  Map<Mood, int> get moodCounts {
    final counts = <Mood, int>{for (final m in Mood.values) m: 0};
    for (final e in entries) {
      counts[e.mood] = (counts[e.mood] ?? 0) + 1;
    }
    return counts;
  }

  Map<Emotion, int> get emotionCounts {
    final counts = <Emotion, int>{};
    for (final e in entries) {
      for (final emotion in e.emotions) {
        counts[emotion] = (counts[emotion] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// Most frequently recorded mood, or `null` when there are no entries.
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

  /// Mean energy per mood, only for moods that appear in the range.
  Map<Mood, double> get averageEnergyByMood {
    final byMood = <Mood, List<int>>{};
    for (final e in entries) {
      byMood.putIfAbsent(e.mood, () => []).add(e.energy);
    }
    final result = <Mood, double>{};
    for (final entry in byMood.entries) {
      final total = entry.value.fold<int>(0, (sum, v) => sum + v);
      result[entry.key] = total / entry.value.length;
    }
    return result;
  }

  /// Consecutive check-in streak ending on or before [today].
  int currentStreak({DateTime? today}) {
    final ref = AppDates.dateOnly(today ?? DateTime.now());
    final dayKeys = <String>{};
    for (final e in entries) {
      dayKeys.add(AppDates.dateKey(e.date));
    }
    var streak = 0;
    var cursor = ref;
    while (dayKeys.contains(AppDates.dateKey(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// Longest streak of consecutive days with check-ins across all data.
  int longestStreak() {
    if (entries.isEmpty) return 0;
    final sorted = List<DateTime>.of(
      entries.map((e) => AppDates.dateOnly(e.date)),
    )..sort();
    final uniq = <DateTime>[];
    for (final d in sorted) {
      if (uniq.isEmpty || AppDates.dateKey(d) != AppDates.dateKey(uniq.last)) {
        uniq.add(d);
      }
    }
    var best = 1;
    var current = 1;
    for (var i = 1; i < uniq.length; i++) {
      if (uniq[i].difference(uniq[i - 1]).inDays == 1) {
        current++;
      } else {
        if (current > best) best = current;
        current = 1;
      }
    }
    return current > best ? current : best;
  }

  /// Local days in [from]..[to] that have no check-in.
  List<DateTime> missingDaysInRange({DateTime? from, DateTime? to}) {
    final start = from ?? rangeStart;
    final end = to ?? rangeEnd;
    if (start == null || end == null) return const [];
    final present = <String>{};
    for (final e in entries) {
      present.add(AppDates.dateKey(e.date));
    }
    final missing = <DateTime>[];
    var cursor = AppDates.dateOnly(start);
    final endDay = AppDates.dateOnly(end);
    while (!cursor.isAfter(endDay)) {
      if (!present.contains(AppDates.dateKey(cursor))) {
        missing.add(cursor);
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return missing;
  }
}

/// Pure analytics over saved [MoodEntry] lists. No Flutter/SQLite dependency.
class MoodAnalyticsService {
  MoodAnalyticsService();

  /// Filters [entries] to an inclusive local-date range and builds analytics.
  MoodAnalytics analyze(
    List<MoodEntry> entries, {
    DateTime? from,
    DateTime? to,
  }) {
    final filtered = entries.where((e) {
      final d = AppDates.dateOnly(e.date);
      if (from != null && d.isBefore(AppDates.dateOnly(from))) return false;
      if (to != null && d.isAfter(AppDates.dateOnly(to))) return false;
      return true;
    }).toList()..sort((a, b) => a.date.compareTo(b.date));
    return MoodAnalytics(entries: filtered, rangeStart: from, rangeEnd: to);
  }

  /// All entries as analytics (no date filter).
  MoodAnalytics analyzeAll(List<MoodEntry> entries) => analyze(entries);

  /// Daily average energy scores for the last [days] local days (oldest first).
  /// Only days with a check-in are included — no gaps are invented.
  static List<MapEntry<DateTime, double>> dailyEnergyScores(
    List<MoodEntry> entries, {
    int days = 14,
    DateTime? today,
  }) {
    final now = AppDates.dateOnly(today ?? DateTime.now());
    final start = now.subtract(Duration(days: days - 1));
    final byDay = <DateTime, List<int>>{};
    for (final entry in entries) {
      if (entry.date.isBefore(start) || entry.date.isAfter(now)) continue;
      byDay
          .putIfAbsent(AppDates.dateOnly(entry.date), () => [])
          .add(entry.energy);
    }
    final result = byDay.entries.map((e) {
      final avg = e.value.fold<int>(0, (a, b) => a + b) / e.value.length;
      return MapEntry(e.key, avg);
    }).toList()..sort((a, b) => a.key.compareTo(b.key));
    return result;
  }
}
