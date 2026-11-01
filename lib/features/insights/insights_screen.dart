import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/theme/app_colors.dart';
import '../../models/mood.dart';
import '../../services/stats_service.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_section.dart';
import '../../widgets/section_header.dart';
import '../../widgets/status_views.dart';
import '../check_in/mood_check_in_screen.dart';

/// Insights computed strictly from saved entries: mood distribution, average
/// energy, recent trend and most frequent emotions. Never fabricates data.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => InsightsScreenState();
}

class InsightsScreenState extends State<InsightsScreen> {
  StatsPeriod _period = StatsPeriod.week;
  MoodStats? _stats;
  List<MapEntry<DateTime, double>> _daily = const [];
  int _totalEntries = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  /// Called by the shell when this tab is (re)selected.
  Future<void> refresh() => _load();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = AppServices.of(context).moodRepository;
      final all = await repository.getAll();
      if (!mounted) return;
      final filtered = StatsService.filterPeriod(all, _period);
      setState(() {
        _totalEntries = all.length;
        _stats = StatsService.compute(
          entries: filtered,
          period: _period,
          allEntries: all,
        );
        _daily = StatsService.dailyScores(all, days: 14);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not compute your insights.';
      });
    }
  }

  void _setPeriod(StatsPeriod period) {
    setState(() => _period = period);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const LoadingState(label: 'Crunching your numbers…')
              : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _stats == null || _totalEntries == 0
              ? ListView(
                  padding: const EdgeInsets.only(top: 40),
                  children: [
                    EmptyState(
                      icon: Icons.insights_rounded,
                      title: 'No insights yet',
                      message: 'Check in with your mood for a few days and trends will appear here.',
                      actionLabel: 'Check in now',
                      onAction: () async {
                        final saved = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => const MoodCheckInScreen(),
                          ),
                        );
                        if (saved == true && mounted) refresh();
                      },
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                  children: [
                    _buildPeriodSelector(theme),
                    const SizedBox(height: 16),
                    AnimatedSection(child: _buildSummaryRow(theme)),
                    const SizedBox(height: 14),
                    AnimatedSection(child: _buildDistributionCard(theme)),
                    const SizedBox(height: 14),
                    AnimatedSection(child: _buildTrendCard(theme)),
                    const SizedBox(height: 14),
                    AnimatedSection(child: _buildEmotionsCard(theme)),
                    const SizedBox(height: 14),
                    AnimatedSection(child: _buildReflectionCard(theme)),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildPeriodSelector(ThemeData theme) {
    return SegmentedButton<StatsPeriod>(
      segments: const [
        ButtonSegment(value: StatsPeriod.week, label: Text('This week')),
        ButtonSegment(value: StatsPeriod.month, label: Text('This month')),
        ButtonSegment(value: StatsPeriod.allTime, label: Text('All time')),
      ],
      selected: {_period},
      onSelectionChanged: (selection) => _setPeriod(selection.first),
      showSelectedIcon: false,
    );
  }

  Widget _buildSummaryRow(ThemeData theme) {
    final stats = _stats!;
    final avgMood = stats.averageMoodScore;
    final avgEnergy = stats.averageEnergy;
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            label: 'Average mood',
            value: avgMood == null ? '—' : avgMood.toStringAsFixed(1),
            caption: avgMood == null
                ? 'No entries in range'
                : (stats.dominantMood?.label ?? ''),
            icon: stats.dominantMood?.icon ?? Icons.mood_rounded,
            color: stats.dominantMood?.color ?? AppColors.primary,
            sub:
                'out of 5 · ${stats.totalEntries} '
                '${stats.totalEntries == 1 ? 'check-in' : 'check-ins'}',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            label: 'Average energy',
            value: avgEnergy == null ? '—' : avgEnergy.toStringAsFixed(1),
            caption: '',
            icon: Icons.bolt_rounded,
            color: AppColors.primary,
            sub: 'out of 5',
          ),
        ),
      ],
    );
  }

  Widget _buildDistributionCard(ThemeData theme) {
    final stats = _stats!;
    final counts = stats.moodCounts;
    final maxCount = counts.values.fold<int>(0, (max, c) => c > max ? c : max);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mood distribution', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(_periodLabel(), style: theme.textTheme.bodySmall),
          const SizedBox(height: 18),
          SizedBox(
            height: 170,
            child: BarChart(
              BarChartData(
                maxY: (maxCount + 1).toDouble(),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final mood = Mood.values[group.x.toInt()];
                      final count = rod.toY.toInt();
                      return BarTooltipItem(
                        '${mood.label}\n$count ${count == 1 ? 'entry' : 'entries'}',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: [
                  for (final mood in Mood.values)
                    BarChartGroupData(
                      x: mood.index,
                      barRods: [
                        BarChartRodData(
                          toY: (counts[mood] ?? 0).toDouble(),
                          width: 22,
                          color: mood.color,
                          borderRadius: BorderRadius.circular(7),
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
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: _niceInterval(maxCount + 1),
                      getTitlesWidget: (value, meta) => Text(
                        '${value.toInt()}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= Mood.values.length) {
                          return const SizedBox.shrink();
                        }
                        final mood = Mood.values[index];
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Icon(mood.icon, size: 18, color: mood.color),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (final mood in Mood.values)
                Text(
                  '${mood.label} ${counts[mood] ?? 0}',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrendCard(ThemeData theme) {
    final stats = _stats!;
    final trend = stats.trend;
    final daily = _daily;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recent trend', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Last 7 days vs the 7 before · daily average mood',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _TrendChip(trend: trend),
              const Spacer(),
              if (trend.currentAverage != null && trend.previousAverage != null)
                Text(
                  '${trend.previousAverage!.toStringAsFixed(1)} → ${trend.currentAverage!.toStringAsFixed(1)}',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
          if (daily.length >= 2) ...[
            const SizedBox(height: 16),
            SizedBox(height: 140, child: _DailyTrendChart(spots: daily)),
            const SizedBox(height: 6),
            Text(
              'Daily average over the last 14 days',
              style: theme.textTheme.bodySmall,
            ),
          ] else ...[
            const SizedBox(height: 12),
            Text(
              'Keep checking in daily to see your mood curve.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmotionsCard(ThemeData theme) {
    final stats = _stats!;
    final top = stats.topEmotions.take(5).toList();
    final maxCount = top.isEmpty ? 0 : top.first.value;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Top emotions', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(_periodLabel(), style: theme.textTheme.bodySmall),
          const SizedBox(height: 14),
          if (top.isEmpty)
            Text(
              'No emotions tagged in this range yet.',
              style: theme.textTheme.bodySmall,
            )
          else
            for (final item in top) ...[
              Row(
                children: [
                  Icon(
                    item.key.icon,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 84,
                    child: Text(
                      item.key.label,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: maxCount == 0 ? 0 : item.value / maxCount,
                        minHeight: 8,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('${item.value}', style: theme.textTheme.titleSmall),
                ],
              ),
              if (item != top.last) const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  Widget _buildReflectionCard(ThemeData theme) {
    final stats = _stats;
    final isFew =
        stats != null && stats.totalEntries > 0 && stats.totalEntries < 4;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.spa_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text('Personal Reflection', style: theme.textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Moodly is an offline tool designed for mindful self-reflection and personal wellness. '
            'These insights summarize your recorded entries to help you recognize your personal rhythms and are not medical diagnoses, mental health evaluations, or clinical advice.',
            style: theme.textTheme.bodySmall,
          ),
          if (isFew) ...[
            const SizedBox(height: 10),
            AppSection(
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Notice: You have only ${stats.totalEntries} ${stats.totalEntries == 1 ? 'entry' : 'entries'} recorded in this timeframe. Early statistics may not yet reflect meaningful patterns. Patterns become clearer with consistent daily check-ins.',
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _periodLabel() {
    switch (_period) {
      case StatsPeriod.week:
        return 'This week (Monday – today)';
      case StatsPeriod.month:
        return 'This month so far';
      case StatsPeriod.allTime:
        return 'All recorded entries';
    }
  }

  double _niceInterval(int max) {
    if (max <= 6) return 1;
    if (max <= 12) return 2;
    return (max / 6).ceilToDouble();
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.color,
    required this.sub,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color color;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.headlineLarge?.copyWith(color: color),
          ),
          const SizedBox(height: 2),
          Text(sub, style: theme.textTheme.bodySmall),
          if (caption.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Mostly $caption', style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _TrendChip extends StatelessWidget {
  const _TrendChip({required this.trend});

  final MoodTrend trend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, label, color) = switch (trend.direction) {
      TrendDirection.improving => (
        Icons.trending_up_rounded,
        'Improving',
        const Color(0xFF5DBFA0),
      ),
      TrendDirection.declining => (
        Icons.trending_down_rounded,
        'Slipping',
        AppColors.danger,
      ),
      TrendDirection.steady => (
        Icons.trending_flat_rounded,
        'Steady',
        AppColors.primary,
      ),
      TrendDirection.unknown => (
        Icons.remove_rounded,
        'Not enough data yet',
        theme.colorScheme.onSurfaceVariant,
      ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.titleSmall?.copyWith(color: color)),
      ],
    );
  }
}

class _DailyTrendChart extends StatelessWidget {
  const _DailyTrendChart({required this.spots});

  final List<MapEntry<DateTime, double>> spots;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LineChart(
      LineChartData(
        minY: 1,
        maxY: 5,
        minX: 0,
        maxX: (spots.length - 1).toDouble(),
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final index = spot.spotIndex;
                final day = spots[index].key;
                return LineTooltipItem(
                  '${day.month}/${day.day}\n${spot.y.toStringAsFixed(1)}',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
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
              getTitlesWidget: (value, meta) =>
                  Text('${value.toInt()}', style: theme.textTheme.bodySmall),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: _bottomInterval(),
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= spots.length) {
                  return const SizedBox.shrink();
                }
                final day = spots[index].key;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${day.month}/${day.day}',
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
              for (var i = 0; i < spots.length; i++)
                FlSpot(i.toDouble(), spots[i].value),
            ],
            isCurved: true,
            preventCurveOverShooting: true,
            barWidth: 3,
            color: AppColors.primary,
            dotData: FlDotData(show: spots.length <= 8),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.primary.withValues(alpha: 0.10),
            ),
          ),
        ],
      ),
    );
  }

  double _bottomInterval() {
    if (spots.length <= 4) return 1;
    if (spots.length <= 8) return 2;
    return 3;
  }
}
