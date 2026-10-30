import 'package:moodly/core/utils/date_utils.dart';
import 'package:moodly/models/emotion.dart';
import 'package:moodly/models/mood.dart';
import 'package:moodly/models/mood_entry.dart';
import 'package:moodly/services/mood_analytics_service.dart';

/// A detected pattern with the data that supports it.
class MoodPattern {
  const MoodPattern({
    required this.title,
    required this.description,
    required this.evidence,
    required this.type,
    this.confidence = 0.5,
    this.rangeStart,
    this.rangeEnd,
    this.dataPointCount = 0,
  });

  final String title;
  final String description;
  final String evidence;
  final MoodPatternType type;
  final double confidence;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final int dataPointCount;
}

enum MoodPatternType { consistency, mood, energy, emotion, streak, gap }

/// Local rule-based mood-pattern detection.
///
/// Nothing here is machine learning. Every pattern is a transparent
/// calculation over the user's own saved entries.
class MoodPatternService {
  MoodPatternService();

  /// Detects explainable patterns from [analytics] and [allEntries].
  List<MoodPattern> detectPatterns(
    MoodAnalytics analytics,
    List<MoodEntry> allEntries, {
    DateTime? today,
  }) {
    final patterns = <MoodPattern>[];
    final now = AppDates.dateOnly(today ?? DateTime.now());
    final entries = analytics.entries;

    if (entries.isEmpty) return patterns;

    // 1. Consistency over the last 7 days.
    final last7Start = now.subtract(const Duration(days: 6));
    final recent7 = entries
        .where((e) => !e.date.isBefore(last7Start) && !e.date.isAfter(now))
        .toList();
    final recent7Days = <String>{};
    for (final e in recent7) {
      recent7Days.add(AppDates.dateKey(e.date));
    }
    if (recent7Days.length >= 4) {
      patterns.add(
        MoodPattern(
          title: 'Checking in consistently',
          description:
              'You recorded a mood on ${recent7Days.length} of the last 7 days.',
          evidence: 'Last 7 days: ${recent7Days.length} check-in days.',
          type: MoodPatternType.consistency,
          confidence: 0.8,
          rangeStart: last7Start,
          rangeEnd: now,
          dataPointCount: recent7Days.length,
        ),
      );
    } else if (recent7Days.isNotEmpty) {
      patterns.add(
        MoodPattern(
          title: 'Check-in rhythm',
          description:
              'You recorded a mood on ${recent7Days.length} of the last 7 days. A daily habit helps patterns emerge.',
          evidence: 'Last 7 days: ${recent7Days.length} check-in days.',
          type: MoodPatternType.consistency,
          confidence: 0.5,
          rangeStart: last7Start,
          rangeEnd: now,
          dataPointCount: recent7Days.length,
        ),
      );
    }

    // 2. Most frequent mood.
    final dominant = analytics.dominantMood;
    if (dominant != null) {
      final count = analytics.moodCounts[dominant] ?? 0;
      final share = analytics.totalEntries > 0
          ? (count / analytics.totalEntries * 100).toStringAsFixed(0)
          : '0';
      patterns.add(
        MoodPattern(
          title: 'Your most frequent mood',
          description:
              '${dominant.label} is your most common mood ($share% of entries).',
          evidence:
              '$count ${dominant.label} entries out of ${analytics.totalEntries} total.',
          type: MoodPatternType.mood,
          confidence: 0.7,
          dataPointCount: analytics.totalEntries,
        ),
      );
    }

    // 3. Good/Great days in the last 7.
    final goodGreat = recent7
        .where((e) => e.mood == Mood.good || e.mood == Mood.great)
        .length;
    if (recent7.isNotEmpty) {
      patterns.add(
        MoodPattern(
          title: 'Good days lately',
          description:
              'You recorded Good or Great moods on $goodGreat of the last ${recent7.length} days.',
          evidence:
              '$goodGreat Good/Great entries out of ${recent7.length} in the last 7 days.',
          type: MoodPatternType.mood,
          confidence: 0.6,
          rangeStart: last7Start,
          rangeEnd: now,
          dataPointCount: recent7.length,
        ),
      );
    }

    // 4. Energy on Motivated vs non-Motivated days.
    final motivatedDays = entries
        .where((e) => e.emotions.contains(Emotion.motivated))
        .toList();
    final notMotivated = entries
        .where((e) => !e.emotions.contains(Emotion.motivated))
        .toList();
    if (motivatedDays.length >= 2 && notMotivated.length >= 2) {
      final motAvg =
          motivatedDays.fold<int>(0, (s, e) => s + e.energy) /
          motivatedDays.length;
      final notAvg =
          notMotivated.fold<int>(0, (s, e) => s + e.energy) /
          notMotivated.length;
      if ((motAvg - notAvg).abs() >= 0.5) {
        final higher = motAvg > notAvg ? 'higher' : 'lower';
        patterns.add(
          MoodPattern(
            title: 'Energy and motivation',
            description:
                'Your average energy was $higher on days you tagged Motivated.',
            evidence:
                'Motivated avg ${motAvg.toStringAsFixed(1)} vs others ${notAvg.toStringAsFixed(1)}.',
            type: MoodPatternType.energy,
            confidence: 0.6,
            dataPointCount: entries.length,
          ),
        );
      }
    }

    // 5. Stress / anxiety frequency.
    final stressedEntries = entries
        .where((e) => e.emotions.contains(Emotion.stressed))
        .toList();
    final anxiousEntries = entries
        .where((e) => e.emotions.contains(Emotion.anxious))
        .toList();
    final difficult = stressedEntries.length + anxiousEntries.length;
    if (difficult >= 2 && analytics.totalEntries >= 3) {
      patterns.add(
        MoodPattern(
          title: 'Tense emotions appeared',
          description:
              'Stress or anxiety showed up in $difficult of your ${analytics.totalEntries} entries.',
          evidence:
              '${stressedEntries.length} stressed · ${anxiousEntries.length} anxious entries.',
          type: MoodPatternType.emotion,
          confidence: 0.55,
          dataPointCount: analytics.totalEntries,
        ),
      );
    }

    // 6. Current check-in streak.
    final streak = analytics.currentStreak(today: now);
    if (streak >= 3) {
      patterns.add(
        MoodPattern(
          title: 'Current check-in streak',
          description:
              'You have checked in $streak ${streak == 1 ? 'day' : 'days'} in a row.',
          evidence: 'Consecutive days ending $now.',
          type: MoodPatternType.streak,
          confidence: 0.9,
          rangeEnd: now,
          dataPointCount: streak,
        ),
      );
    }

    // 7. Missing days in the last 30 days (only when some data exists).
    final last30Start = now.subtract(const Duration(days: 29));
    final missing = analytics.missingDaysInRange(from: last30Start, to: now);
    if (missing.isNotEmpty && missing.length <= 10) {
      patterns.add(
        MoodPattern(
          title: 'Days without check-ins',
          description:
              'You missed ${missing.length} day${missing.length == 1 ? '' : 's'} in the last 30 days.',
          evidence: 'Gaps in the last 30 local days.',
          type: MoodPatternType.gap,
          confidence: 0.6,
          rangeStart: last30Start,
          rangeEnd: now,
          dataPointCount: missing.length,
        ),
      );
    }

    return patterns;
  }
}
