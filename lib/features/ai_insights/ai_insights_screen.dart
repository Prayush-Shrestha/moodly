import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../app.dart';
import '../check_in/mood_check_in_screen.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/formatters.dart';
import '../../models/emotion.dart';
import '../../models/insight_card.dart';
import '../../models/mood_entry.dart';
import '../../services/mood_analytics_service.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_section.dart';
import '../../widgets/section_header.dart';
import '../../widgets/status_views.dart';
import 'ai_insights_view_model.dart';

/// AI-powered insights screen built entirely from real saved entries.
///
/// Every insight is a rule-based calculation over the user's own data;
/// nothing is invented, and nothing is a medical diagnosis.
class AiInsightsScreen extends StatefulWidget {
  const AiInsightsScreen({super.key});

  @override
  State<AiInsightsScreen> createState() => _AiInsightsScreenState();
}

class _AiInsightsScreenState extends State<AiInsightsScreen> {
  late final AiInsightsViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = AiInsightsViewModel(
      moodRepository: AppServices.of(context).moodRepository,
    );
    _viewModel.addListener(_onChanged);
    _viewModel.load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onChanged);
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('AI Insights')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _viewModel.load(),
          child: _viewModel.loading
              ? const LoadingState(label: 'Reading your entries…')
              : _viewModel.error != null
              ? ErrorState(
                  message: _viewModel.error!,
                  onRetry: () => _viewModel.load(),
                )
              : _viewModel.totalEntries == 0
              ? _buildEmpty(theme)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                  children: [
                    _buildCoverageCard(theme),
                    const SizedBox(height: 14),
                    _buildPeriodSelector(theme),
                    const SizedBox(height: 14),
                    SectionHeader(title: 'Your insights'),
                    ..._buildInsightCards(theme),
                    const SizedBox(height: 14),
                    SectionHeader(title: 'Weekly mood'),
                    _buildWeeklyMood(theme),
                    const SizedBox(height: 14),
                    SectionHeader(title: 'Emotion patterns'),
                    _buildEmotionChart(theme),
                    const SizedBox(height: 14),
                    SectionHeader(title: 'Energy trend'),
                    _buildEnergyChart(theme),
                    const SizedBox(height: 14),
                    _buildDisclaimer(theme),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.only(top: 40),
      children: [
        EmptyState(
          icon: Icons.insights_rounded,
          title: 'No insights yet',
          message: 'Check in with your mood for a few days, and patterns will appear here.',
          actionLabel: 'Check in now',
          onAction: () async {
            final saved = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => const MoodCheckInScreen()),
            );
            if (saved == true && mounted) _viewModel.load();
          },
        ),
      ],
    );
  }

  Widget _buildCoverageCard(ThemeData theme) {
    final vm = _viewModel;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Data coverage', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _CoverageStat(
                  label: 'Total check-ins',
                  value: '${vm.totalEntries}',
                ),
              ),
              Expanded(
                child: _CoverageStat(
                  label: 'Days checked in',
                  value: '${vm.checkInDays}',
                ),
              ),
              Expanded(
                child: _CoverageStat(
                  label: 'Current streak',
                  value: '${vm.currentStreak}',
                  caption: 'days in a row',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (vm.averageEnergy != null)
            Text(
              'Average energy: ${vm.averageEnergy!.toStringAsFixed(1)} / 5',
              style: theme.textTheme.bodyMedium,
            ),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector(ThemeData theme) {
    return SegmentedButton<AiInsightsPeriod>(
      segments: const [
        ButtonSegment(value: AiInsightsPeriod.week, label: Text('This week')),
        ButtonSegment(value: AiInsightsPeriod.month, label: Text('This month')),
        ButtonSegment(value: AiInsightsPeriod.allTime, label: Text('All time')),
      ],
      selected: {_viewModel.period},
      onSelectionChanged: (selection) => _viewModel.setPeriod(selection.first),
      showSelectedIcon: false,
    );
  }

  List<Widget> _buildInsightCards(ThemeData theme) {
    final widgets = <Widget>[];
    for (final insight in _viewModel.insights) {
      widgets.add(_buildInsightCard(theme, insight));
      widgets.add(const SizedBox(height: 10));
    }
    return widgets;
  }

  Widget _buildInsightCard(ThemeData theme, InsightCard insight) {
    final color = insight.typeColor;
    return AppCard(
      color: color.withValues(alpha: 0.08),
      borderColor: color.withValues(alpha: 0.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  insight.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  insight.confidenceLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(insight.description, style: theme.textTheme.bodyMedium),
          if (insight.evidence != null && insight.evidence!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Based on: ${insight.evidence}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (insight.dateRangeStart != null ||
              insight.dateRangeEnd != null) ...[
            const SizedBox(height: 6),
            Text(
              'Range: ${_rangeText(insight)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _rangeText(InsightCard insight) {
    final parts = <String>[];
    if (insight.dateRangeStart != null) {
      parts.add(Formatters.mediumDate(insight.dateRangeStart!));
    }
    if (insight.dateRangeEnd != null) {
      parts.add(Formatters.mediumDate(insight.dateRangeEnd!));
    }
    return parts.join(' – ');
  }

  Widget _buildWeeklyMood(ThemeData theme) {
    final now = AppDates.dateOnly(DateTime.now());
    final days = AppDates.daysInRange(AppDates.startOfWeek(now), now);
    final byDay = <String, MoodEntry>{};
    for (final e in _viewModel.entries) {
      byDay[AppDates.dateKey(e.date)] = e;
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: Row(
              children: [
                for (var i = 0; i < days.length; i++) ...[
                  Expanded(
                    child: _DayDot(
                      date: days[i],
                      entry: byDay[AppDates.dateKey(days[i])],
                    ),
                  ),
                  if (i < days.length - 1) const SizedBox(width: 10),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Colored dots show your mood that day; empty dots are days without a check-in.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildEmotionChart(ThemeData theme) {
    final emotionCounts = _viewModel.analytics?.emotionCounts ?? {};
    if (emotionCounts.isEmpty) {
      return AppCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No emotion tags yet.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }
    final top = emotionCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final max = top.first.value.toDouble();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                maxY: max + 1,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final emotion = Emotion.values[group.x.toInt()];
                      return BarTooltipItem(
                        '${emotion.label}: ${rod.toY.toInt()}',
                        const TextStyle(color: Colors.white, fontSize: 12),
                      );
                    },
                  ),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: [
                  for (var i = 0; i < Emotion.values.length; i++)
                    if (emotionCounts.containsKey(Emotion.values[i]))
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: emotionCounts[Emotion.values[i]]!.toDouble(),
                            width: 18,
                            color: _emotionColor(Emotion.values[i]),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ],
                      ),
                ],
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= Emotion.values.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            Emotion.values[index].label.substring(0, 3),
                            style: theme.textTheme.bodySmall,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: top.take(6).map((e) {
              return Chip(
                label: Text(e.key.label),
                avatar: Icon(e.key.icon, size: 16),
                backgroundColor: _emotionColor(e.key).withValues(alpha: 0.12),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Color _emotionColor(Emotion e) {
    switch (e) {
      case Emotion.calm:
      case Emotion.happy:
      case Emotion.excited:
      case Emotion.grateful:
      case Emotion.motivated:
        return AppColors.primary;
      default:
        return AppColors.danger;
    }
  }

  Widget _buildEnergyChart(ThemeData theme) {
    final daily = MoodAnalyticsService.dailyEnergyScores(
      _viewModel.entries,
      days: 14,
    );
    if (daily.isEmpty) {
      return AppCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('No energy data yet.', style: theme.textTheme.bodyMedium),
        ),
      );
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                minY: 1,
                maxY: 5,
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final index = spot.spotIndex.toInt();
                        return LineTooltipItem(
                          '${Formatters.mediumDate(daily[index].key)}\n${spot.y.toStringAsFixed(1)}',
                          const TextStyle(color: Colors.white, fontSize: 12),
                        );
                      }).toList();
                    },
                  ),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      interval: 1,
                      getTitlesWidget: (value, meta) => Text(
                        '${value.toInt()}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: 3,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= daily.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${daily[index].key.month}/${daily[index].key.day}',
                            style: theme.textTheme.bodySmall,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < daily.length; i++)
                        FlSpot(i.toDouble(), daily[i].value),
                    ],
                    isCurved: true,
                    preventCurveOverShooting: true,
                    barWidth: 3,
                    color: AppColors.primary,
                    dotData: FlDotData(show: daily.length <= 8),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.primary.withValues(alpha: 0.10),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Daily average energy over the last 14 days (days with entries only).',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildDisclaimer(ThemeData theme) {
    return AppCard(
      color: theme.colorScheme.surfaceContainerHighest,
      child: AppSection(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'About these insights',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Moodly insights are calculated from your own saved mood check-ins '
              'and journal entries using simple, explainable rules. They are for '
              'personal reflection only and are not medical diagnoses, mental '
              'health evaluations, or clinical advice. Patterns may not be '
              'meaningful with only a few entries.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Small colored dot for one day (used in the weekly mood row).
class _DayDot extends StatelessWidget {
  const _DayDot({required this.date, required this.entry});

  final DateTime date;
  final MoodEntry? entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mood = entry?.mood;
    return Semantics(
      label: mood == null
          ? 'No check-in on ${Formatters.mediumDate(date)}'
          : '${Formatters.mediumDate(date)}: ${mood.label}',
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: mood == null
              ? theme.colorScheme.surfaceContainerHighest
              : mood.tint,
        ),
        child: mood == null
            ? null
            : Center(child: Icon(mood.icon, size: 16, color: mood.color)),
      ),
    );
  }
}

class _CoverageStat extends StatelessWidget {
  const _CoverageStat({required this.label, required this.value, this.caption});

  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: theme.textTheme.headlineLarge),
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
