import '../core/network/api_client.dart';
import '../core/utils/date_utils.dart';
import '../models/mood.dart';
import '../models/report.dart';
import '../repositories/mood_repository.dart';
import '../repositories/report_repository.dart';
import '../repositories/settings_repository.dart';
import 'auth_service.dart';
import 'mood_analytics_service.dart';

/// Builds weekly and monthly mood reports from the user's REAL saved records.
///
/// - Statistics always come from local SQLite data (works fully offline).
/// - The narrative is written locally by explainable rules. When the user is
///   signed in with AI-processing consent, an AI narrative generated from the
///   same aggregates (never journal text) replaces it, clearly labelled.
/// - Comparisons with the previous period appear only when both periods have
///   enough data — no invented numbers.
class ReportService {
  ReportService({
    required MoodRepository moodRepository,
    required ReportRepository reportRepository,
    required this._api,
    required this._auth,
    required this._settings,
  }) : _moods = moodRepository,
       _reports = reportRepository;

  static const int _minEntriesForComparison = 3;

  final MoodRepository _moods;
  final ReportRepository _reports;
  final ApiClient _api;
  final AuthService _auth;
  final SettingsRepository _settings;

  // --- public API ---------------------------------------------------------------

  Future<MoodReport?> getSavedReport(String kind, DateTime periodStart) =>
      _reports.getForPeriod(kind, periodStart);

  Future<List<MoodReport>> history() => _reports.getAll();

  Future<void> deleteReport(int id) => _reports.delete(id);

  /// Current (in-progress) week window: Monday..today.
  static ({DateTime start, DateTime end}) currentWeek({DateTime? now}) {
    final today = AppDates.dateOnly(now ?? DateTime.now());
    final start = AppDates.startOfWeek(today);
    return (start: start, end: today);
  }

  /// Current (in-progress) month window: 1st..today.
  static ({DateTime start, DateTime end}) currentMonth({DateTime? now}) {
    final today = AppDates.dateOnly(now ?? DateTime.now());
    return (start: DateTime(today.year, today.month), end: today);
  }

  static ({DateTime start, DateTime end}) previousWeek({DateTime? now}) {
    final week = currentWeek(now: now);
    final end = week.start.subtract(const Duration(days: 1));
    return (start: AppDates.startOfWeek(end), end: end);
  }

  static ({DateTime start, DateTime end}) previousMonth({DateTime? now}) {
    final month = currentMonth(now: now);
    final end = DateTime(month.start.year, month.start.month, 0);
    return (start: DateTime(end.year, end.month), end: end);
  }

  /// Generates (and persists) the current weekly report.
  Future<MoodReport> generateWeeklyReport({DateTime? now}) async {
    final window = currentWeek(now: now);
    return _generate(
      kind: MoodReport.kindWeekly,
      start: window.start,
      end: window.end,
      label: 'Weekly report',
      previous: previousWeek(now: now),
      includeComparison: false,
    );
  }

  /// Generates (and persists) the current monthly report.
  Future<MoodReport> generateMonthlyReport({DateTime? now}) async {
    final window = currentMonth(now: now);
    return _generate(
      kind: MoodReport.kindMonthly,
      start: window.start,
      end: window.end,
      label: 'Monthly report',
      previous: previousMonth(now: now),
      includeComparison: true,
    );
  }

  // --- internals -----------------------------------------------------------------

  Future<MoodReport> _generate({
    required String kind,
    required DateTime start,
    required DateTime end,
    required String label,
    required ({DateTime start, DateTime end}) previous,
    required bool includeComparison,
  }) async {
    final all = await _moods.getAll();
    final analyticsService = MoodAnalyticsService();

    final current = analyticsService.analyze(all, from: start, to: end);
    final stats = _statsFor(current, start: start, end: end);

    Map<String, Object?>? comparison;
    String? comparisonSentence;
    if (includeComparison) {
      final prev = analyticsService.analyze(
        all,
        from: previous.start,
        to: previous.end,
      );
      if (prev.totalEntries >= _minEntriesForComparison &&
          current.totalEntries >= _minEntriesForComparison) {
        final prevStats = _statsFor(
          prev,
          start: previous.start,
          end: previous.end,
        );
        final curMood = (stats['averageMoodScore'] as double?) ?? 0;
        final prevMood = (prevStats['averageMoodScore'] as double?) ?? 0;
        final curEnergy = (stats['averageEnergy'] as double?) ?? 0;
        final prevEnergy = (prevStats['averageEnergy'] as double?) ?? 0;
        comparison = {
          'previousPeriod': prevStats,
          'avgMoodDelta': _round(curMood - prevMood),
          'avgEnergyDelta': _round(curEnergy - prevEnergy),
          'checkInDelta':
              (stats['checkInDays'] as int) - (prevStats['checkInDays'] as int),
        };
        comparisonSentence = _comparisonSentence(stats, prevStats);
      }
    }

    var narrativeSource = 'local_rules';
    var narrative = _localNarrative(
      stats: stats,
      label: label,
      start: start,
      end: end,
      comparison: comparisonSentence,
    );
    var questions = _localQuestions(
      stats: stats,
      hasComparison: comparison != null,
    );

    // Optional AI narrative from the same aggregates (never journal text).
    if (_auth.isSignedIn && _settings.aiProcessingConsent) {
      try {
        final payload = await _api.post(
          '/ai/report-narrative',
          body: {
            'period_label': label.toLowerCase(),
            'aggregates': _aggregates(
              stats,
              start: start,
              end: end,
              label: label,
            ),
            'comparison_available': comparison != null,
            'comparison_summary': comparisonSentence,
          },
        );
        final aiNarrative = payload['narrative']?.toString();
        if (aiNarrative != null && aiNarrative.trim().length >= 20) {
          narrative = aiNarrative;
          final rawQuestions = payload['reflection_questions'];
          if (rawQuestions is List && rawQuestions.isNotEmpty) {
            questions = rawQuestions.map((q) => q.toString()).toList();
          }
          narrativeSource = payload['source']?.toString() ?? 'ai:unknown';
        }
      } on ApiException {
        // Offline or AI unavailable → keep the local narrative silently.
      }
    }

    final report = MoodReport(
      kind: kind,
      periodStart: start,
      periodEnd: end,
      periodLabel: _formatRange(start, end),
      data: {
        'stats': stats,
        'comparison': comparison,
        'narrative': narrative,
        'reflectionQuestions': questions,
        'analysisPeriod': {
          'from': AppDates.dateKey(start),
          'to': AppDates.dateKey(end),
        },
      },
      narrativeSource: narrativeSource,
      createdAt: DateTime.now(),
    );
    return _reports.save(report);
  }

  Map<String, Object?> _statsFor(
    MoodAnalytics analytics, {
    required DateTime start,
    required DateTime end,
  }) {
    final moodDist = <String, int>{};
    for (final entry in analytics.moodCounts.entries) {
      if (entry.value > 0) moodDist[entry.key.storageName] = entry.value;
    }
    final emotionEntries = analytics.emotionCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topEmotions = emotionEntries
        .take(5)
        .map(
          (e) => {
            'emotion': e.key.storageName,
            'label': e.key.label,
            'count': e.value,
          },
        )
        .toList();

    final spanDays = end.difference(start).inDays + 1;
    final trend = _trendFor(analytics, start: start, end: end);

    return {
      'totalCheckins': analytics.totalEntries,
      'checkInDays': analytics.checkInDays,
      'spanDays': spanDays < 0 ? 0 : spanDays,
      'moodDistribution': moodDist,
      'mostCommonMood': analytics.dominantMood?.storageName,
      'mostCommonEmotions': topEmotions,
      'averageEnergy': analytics.averageEnergy == null
          ? null
          : _round(analytics.averageEnergy!),
      'averageMoodScore': analytics.averageMoodScore == null
          ? null
          : _round(analytics.averageMoodScore!),
      'longestStreak': analytics.longestStreak(),
      'trend': trend,
    };
  }

  /// Compares the average mood score of the first vs the second half of the
  /// period (only when both halves have check-ins — otherwise `none`).
  Map<String, Object?> _trendFor(
    MoodAnalytics analytics, {
    required DateTime start,
    required DateTime end,
  }) {
    final span = end.difference(start).inDays + 1;
    if (span < 4 || analytics.entries.isEmpty) return {'direction': 'none'};
    final mid = start.add(Duration(days: span ~/ 2));
    double? avgIn(bool firstHalf) {
      final subset = analytics.entries.where((e) {
        final inFirst = e.date.isBefore(mid);
        return firstHalf ? inFirst : !inFirst;
      }).toList();
      if (subset.isEmpty) return null;
      final total = subset.fold<int>(0, (sum, e) => sum + e.mood.score);
      return total / subset.length;
    }

    final first = avgIn(true);
    final second = avgIn(false);
    if (first == null || second == null) return {'direction': 'none'};
    final delta = second - first;
    final direction = delta >= 0.5
        ? 'up'
        : delta <= -0.5
        ? 'down'
        : 'steady';
    return {
      'direction': direction,
      'firstHalfAvg': _round(first),
      'secondHalfAvg': _round(second),
    };
  }

  Map<String, Object?> _aggregates(
    Map<String, Object?> stats, {
    required DateTime start,
    required DateTime end,
    required String label,
  }) {
    final emotions =
        (stats['mostCommonEmotions'] as List?)
            ?.map((e) => (e as Map)['emotion']?.toString() ?? '')
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];
    return {
      'analysis_from': AppDates.dateKey(start),
      'analysis_to': AppDates.dateKey(end),
      'period_label': label.toLowerCase(),
      'total_checkins': stats['totalCheckins'] ?? 0,
      'mood_distribution': stats['moodDistribution'] ?? const <String, int>{},
      'dominant_mood': stats['mostCommonMood'],
      'average_energy': stats['averageEnergy'],
      'top_emotions': emotions,
      'consistent_days': stats['checkInDays'] ?? 0,
      'streak_days': stats['longestStreak'] ?? 0,
    };
  }

  // --- local narrative (explainable rules) ---------------------------------------

  String _localNarrative({
    required Map<String, Object?> stats,
    required String label,
    required DateTime start,
    required DateTime end,
    String? comparison,
  }) {
    final total = (stats['totalCheckins'] as int?) ?? 0;
    if (total == 0) {
      return 'No check-ins were recorded between ${_formatRange(start, end)}, '
          'so this report is empty. Check in on a few days and the report '
          'will start to take shape.';
    }
    final parts = <String>[
      'You logged $total check-in${total == 1 ? '' : 's'} between '
          '${_formatRange(start, end)}.',
    ];
    final mood = stats['mostCommonMood'];
    if (mood is String && mood.isNotEmpty) {
      parts.add(
        'Your most logged mood was ${Mood.fromStorageName(mood).label}.',
      );
    }
    final energy = stats['averageEnergy'];
    if (energy is double) {
      parts.add(
        'Your average energy was ${energy.toStringAsFixed(1)} out of 5.',
      );
    }
    final emotions = stats['mostCommonEmotions'];
    if (emotions is List && emotions.isNotEmpty) {
      final names = emotions
          .take(3)
          .map((e) => (e as Map)['label']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .join(', ');
      parts.add('Recurring emotions included $names.');
    }
    final trend = stats['trend'];
    if (trend is Map && trend['direction'] is String) {
      const labels = {
        'up': 'Your mood ratings trended upward across the period.',
        'down': 'Your mood ratings trended downward across the period.',
        'steady': 'Your mood ratings stayed fairly steady across the period.',
      };
      final sentence = labels[trend['direction']];
      if (sentence != null) parts.add(sentence);
    }
    if (comparison != null) parts.add(comparison);
    return parts.join(' ');
  }

  List<String> _localQuestions({
    required Map<String, Object?> stats,
    required bool hasComparison,
  }) {
    final questions = <String>[];
    final trend = stats['trend'];
    if (trend is Map && trend['direction'] == 'down') {
      questions.add('What felt heavier later in the period than at the start?');
    } else if (trend is Map && trend['direction'] == 'up') {
      questions.add('What seems to have helped your mood improve over time?');
    }
    final emotions = stats['mostCommonEmotions'];
    if (emotions is List && emotions.isNotEmpty) {
      questions.add(
        'Which of your recurring emotions feels most true to this period, '
        'and why?',
      );
    }
    if (hasComparison) {
      questions.add('What would you like to carry into the next period?');
    }
    while (questions.length < 3) {
      questions.add(
        const [
          'What mattered most to you during this period?',
          'Is there anything you want to do differently next period?',
          'What support would make the next period feel easier?',
        ][questions.length],
      );
    }
    return questions.take(3).toList();
  }

  String _comparisonSentence(
    Map<String, Object?> current,
    Map<String, Object?> previous,
  ) {
    final moodDelta =
        ((current['averageMoodScore'] as double?) ?? 0) -
        ((previous['averageMoodScore'] as double?) ?? 0);
    final energyDelta =
        ((current['averageEnergy'] as double?) ?? 0) -
        ((previous['averageEnergy'] as double?) ?? 0);
    final moodWord = moodDelta >= 0.4
        ? 'higher than'
        : moodDelta <= -0.4
        ? 'lower than'
        : 'similar to';
    final energyWord = energyDelta >= 0.4
        ? 'higher than'
        : energyDelta <= -0.4
        ? 'lower than'
        : 'similar to';
    return 'Compared with the previous period, your average mood was '
        '$moodWord and your average energy was $energyWord.';
  }

  static String _formatRange(DateTime start, DateTime end) {
    final s = AppDates.dateOnly(start);
    final e = AppDates.dateOnly(end);
    return '${s.day}/${s.month}/${s.year} – ${e.day}/${e.month}/${e.year}';
  }

  static double _round(double value) => (value * 10).roundToDouble() / 10;
}
