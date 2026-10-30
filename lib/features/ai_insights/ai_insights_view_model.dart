import 'package:flutter/material.dart';

import '../../core/utils/date_utils.dart';
import '../../models/insight_card.dart';
import '../../models/mood_entry.dart';
import '../../repositories/mood_repository.dart';
import '../../services/insight_generation_service.dart';
import '../../services/mood_analytics_service.dart';
import '../../services/mood_pattern_service.dart';

/// Period filter for AI Insights.
enum AiInsightsPeriod { week, month, allTime }

/// Holds AI Insights state and computation, keeping logic out of the widget.
class AiInsightsViewModel extends ChangeNotifier {
  AiInsightsViewModel({required this.moodRepository});

  final MoodRepository moodRepository;

  List<InsightCard> _insights = const [];
  MoodAnalytics? _analytics;
  List<MoodEntry> _entries = const [];
  AiInsightsPeriod _period = AiInsightsPeriod.allTime;
  bool _loading = true;
  String? _error;

  List<InsightCard> get insights => _insights;
  MoodAnalytics? get analytics => _analytics;
  List<MoodEntry> get entries => _entries;
  AiInsightsPeriod get period => _period;
  bool get loading => _loading;
  String? get error => _error;

  int get totalEntries => _analytics?.totalEntries ?? 0;
  int get checkInDays => _analytics?.checkInDays ?? 0;
  double? get averageEnergy => _analytics?.averageEnergy;
  int get currentStreak => _analytics?.currentStreak() ?? 0;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final all = await moodRepository.getAll();
      final now = AppDates.dateOnly(DateTime.now());
      final filtered = _filter(all, now);
      final analytics = MoodAnalyticsService().analyze(
        filtered,
        from: _rangeStart(now),
      );
      final patterns = MoodPatternService().detectPatterns(
        analytics,
        filtered,
        today: now,
      );
      final insights = InsightGenerationService().generateInsights(
        analytics,
        patterns,
      );
      _entries = filtered;
      _analytics = analytics;
      _insights = insights;
    } catch (e) {
      _error = 'Could not compute insights from your entries.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setPeriod(AiInsightsPeriod period) {
    if (_period == period) return;
    _period = period;
    load();
  }

  DateTime? _rangeStart(DateTime now) {
    switch (_period) {
      case AiInsightsPeriod.week:
        return AppDates.startOfWeek(now);
      case AiInsightsPeriod.month:
        return DateTime(now.year, now.month);
      case AiInsightsPeriod.allTime:
        return null;
    }
  }

  List<MoodEntry> _filter(List<MoodEntry> all, DateTime now) {
    final start = _rangeStart(now);
    if (start == null) return List<MoodEntry>.of(all);
    return all.where((e) => !e.date.isBefore(start)).toList();
  }
}
