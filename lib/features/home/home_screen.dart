import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../app.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/formatters.dart';
import '../../models/insight_card.dart';
import '../../models/mood_entry.dart';
import '../../services/insight_generation_service.dart';
import '../../services/mood_analytics_service.dart';
import '../../services/mood_pattern_service.dart';
import '../../widgets/app_card.dart';
import '../../widgets/logo_mark.dart';
import '../../widgets/mood_display.dart';
import '../../widgets/section_header.dart';
import '../../widgets/status_views.dart';
import '../ai_insights/ai_insights_screen.dart';
import '../check_in/mood_check_in_screen.dart';

/// Home dashboard: greeting, today's check-in status, a weekly summary,
/// recent history and quick navigation.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onOpenTab});

  /// Switches to another bottom-nav tab (index matches the shell order).
  final ValueChanged<int> onOpenTab;

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  List<MoodEntry> _recent = const [];
  List<MoodEntry> _week = const [];
  MoodEntry? _todayEntry;
  int _streak = 0;
  InsightCard? _homeInsight;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  /// Called by the shell when this tab is (re)selected.
  Future<void> refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = AppServices.of(context).moodRepository;
      final all = await repository.getAll();
      final now = DateTime.now();
      final weekStart = AppDates.startOfWeek(now);
      final analytics = MoodAnalyticsService().analyzeAll(all);
      final patterns = MoodPatternService().detectPatterns(analytics, all);
      final insights = InsightGenerationService().generateInsights(
        analytics,
        patterns,
      );
      if (!mounted) return;
      setState(() {
        _recent = all.take(5).toList();
        _week = all.where((e) => !e.date.isBefore(weekStart)).toList();
        _todayEntry = all.cast<MoodEntry?>().firstWhere(
          (e) => AppDates.isSameDay(e!.date, now),
          orElse: () => null,
        );
        _streak = analytics.currentStreak();
        _homeInsight = insights.isNotEmpty ? insights.first : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is DatabaseException
            ? 'Could not read your saved moods.'
            : 'Unexpected error.';
      });
    }
  }

  Future<void> _openCheckIn({MoodEntry? existing, DateTime? date}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MoodCheckInScreen(existing: existing, date: date),
      ),
    );
    if (saved == true && mounted) refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: refresh,
          child: _loading
              ? const LoadingState(label: 'Opening your journal…')
              : _error != null
              ? ErrorState(message: _error.toString(), onRetry: refresh)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  children: [
                    _buildHeader(theme),
                    const SizedBox(height: 18),
                    AnimatedSection(child: _buildTodayCard(theme)),
                    const SizedBox(height: 14),
                    AnimatedSection(child: _buildWeekSummary(theme)),
                    const SizedBox(height: 20),
                    if (_homeInsight != null) ...[
                      SectionHeader(title: 'Your insight'),
                      AnimatedSection(child: _buildHomeInsightCard(theme)),
                      const SizedBox(height: 20),
                    ],
                    SectionHeader(
                      title: 'Recent check-ins',
                      actionLabel: 'Calendar',
                      onAction: () => widget.onOpenTab(1),
                    ),
                    AnimatedSection(child: _buildRecent(theme)),
                    const SizedBox(height: 20),
                    SectionHeader(title: 'Explore'),
                    AnimatedSection(child: _buildQuickLinks(theme)),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final now = DateTime.now();
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppDates.greeting(now),
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 2),
              Text(Formatters.longDate(now), style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: 12),
        const LogoMark(size: 40),
      ],
    );
  }

  Widget _buildTodayCard(ThemeData theme) {
    final entry = _todayEntry;
    if (entry == null) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.28),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How are you feeling today?',
              style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              'Take a moment to check in with yourself.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFFE4DBFB),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.deepPurple,
              ),
              onPressed: () => _openCheckIn(),
              icon: const Icon(Icons.add_reaction_outlined),
              label: const Text('Check in'),
            ),
          ],
        ),
      );
    }

    return AppCard(
      onTap: () => _openCheckIn(existing: entry),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text("Today's mood", style: theme.textTheme.bodySmall),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _openCheckIn(existing: entry),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
            ],
          ),
          const SizedBox(height: 2),
          MoodEntryCard(entry: entry, showDate: false),
        ],
      ),
    );
  }

  Widget _buildWeekSummary(ThemeData theme) {
    final days = AppDates.daysInRange(
      AppDates.startOfWeek(DateTime.now()),
      DateTime.now(),
    );
    final byDay = <String, MoodEntry>{
      for (final e in _week) AppDates.dateKey(e.date): e,
    };
    final scores = _week.map((e) => e.mood.score);
    final avgScore = _week.isEmpty
        ? null
        : scores.reduce((a, b) => a + b) / _week.length;
    final avgEnergy = _week.isEmpty
        ? null
        : _week.map((e) => e.energy).reduce((a, b) => a + b) / _week.length;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('This week', style: theme.textTheme.titleMedium),
              const Spacer(),
              Text(
                '${_week.length} ${_week.length == 1 ? 'check-in' : 'check-ins'}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < days.length; i++) ...[
                _DayDot(date: days[i], entry: byDay[AppDates.dateKey(days[i])]),
                if (i < days.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _MiniStat(
                label: 'Avg mood',
                value: avgScore == null
                    ? '—'
                    : '${avgScore.toStringAsFixed(1)} / 5',
              ),
              _MiniStat(
                label: 'Avg energy',
                value: avgEnergy == null
                    ? '—'
                    : '${avgEnergy.toStringAsFixed(1)} / 5',
              ),
              _MiniStat(label: 'Streak', value: '$_streak', caption: 'days'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHomeInsightCard(ThemeData theme) {
    final insight = _homeInsight!;
    final color = insight.typeColor;
    return AppCard(
      color: color.withValues(alpha: 0.08),
      borderColor: color.withValues(alpha: 0.25),
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const AiInsightsScreen())),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(
                    _insightIcon(insight.type),
                    color: color,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      insight.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      insight.description,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: color.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _insightIcon(InsightType type) {
    switch (type) {
      case InsightType.mood:
        return Icons.mood_rounded;
      case InsightType.energy:
        return Icons.bolt_rounded;
      case InsightType.emotion:
        return Icons.favorite_rounded;
      case InsightType.consistency:
        return Icons.repeat_rounded;
      case InsightType.journal:
        return Icons.menu_book_rounded;
    }
  }

  Widget _buildRecent(ThemeData theme) {
    if (_recent.isEmpty) {
      return AppCard(
        child: EmptyState(
          icon: Icons.history_rounded,
          title: 'No check-ins yet',
          message:
              'Your recent moods will appear here after your first check-in.',
          actionLabel: 'Check in now',
          onAction: () => _openCheckIn(),
        ),
      );
    }
    return AppCard(
      child: Column(
        children: [
          for (var i = 0; i < _recent.length; i++) ...[
            MoodEntryCard(
              entry: _recent[i],
              onTap: () => _openCheckIn(existing: _recent[i]),
            ),
            if (i < _recent.length - 1)
              Divider(
                indent: 4,
                endIndent: 4,
                color: theme.colorScheme.outlineVariant,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickLinks(ThemeData theme) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _QuickLink(
          icon: Icons.calendar_month_outlined,
          label: 'Calendar',
          onTap: () => widget.onOpenTab(1),
        ),
        _QuickLink(
          icon: Icons.menu_book_outlined,
          label: 'Journal',
          onTap: () => widget.onOpenTab(2),
        ),
        _QuickLink(
          icon: Icons.insights_rounded,
          label: 'Insights',
          onTap: () => widget.onOpenTab(3),
        ),
        _QuickLink(
          icon: Icons.psychology_rounded,
          label: 'AI Insights',
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AiInsightsScreen())),
        ),
      ],
    );
  }
}

/// Small colored dot for one day of the current week.
class _DayDot extends StatelessWidget {
  const _DayDot({required this.date, required this.entry});

  final DateTime date;
  final MoodEntry? entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isToday = AppDates.isSameDay(date, DateTime.now());
    final mood = entry?.mood;
    return Semantics(
      label: mood == null
          ? 'No check-in on ${Formatters.mediumDate(date)}'
          : '${Formatters.mediumDate(date)}: ${mood.label}',
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: mood == null
              ? theme.colorScheme.surfaceContainerHighest
              : mood.tint,
          border: isToday
              ? Border.all(color: AppColors.primary, width: 1.6)
              : null,
        ),
        child: mood == null
            ? null
            : Icon(mood.icon, size: 17, color: mood.color),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, this.caption});

  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: theme.textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(label, style: theme.textTheme.bodySmall),
        if (caption != null) ...[
          const SizedBox(height: 2),
          Text(caption!, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}

class _QuickLink extends StatelessWidget {
  const _QuickLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(height: 8),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
