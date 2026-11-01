import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/mood.dart';
import '../../models/report.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_section.dart';
import '../../widgets/section_header.dart';

/// Generates, views, saves and shares weekly/monthly mood reports built from
/// the user's real saved records. Works fully offline; the narrative is
/// AI-generated only when the user is signed in with AI consent (labelled).
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => ReportsScreenState();
}

class ReportsScreenState extends State<ReportsScreen> {
  String _kind = MoodReport.kindWeekly;
  MoodReport? _report;
  List<MoodReport> _history = const [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final reports = await AppServices.of(context).reportService.history();
    if (!mounted) return;
    setState(() => _history = reports);
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final service = AppServices.of(context).reportService;
    try {
      final report = _kind == MoodReport.kindWeekly
          ? await service.generateWeeklyReport()
          : await service.generateMonthlyReport();
      if (!mounted) return;
      setState(() {
        _report = report;
        _busy = false;
      });
      await _loadHistory();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not generate the report. Please try again.';
      });
    }
  }

  Future<void> _share(MoodReport report) async {
    final text = ReportTextRenderer.render(report);
    final shared = await AppServices.of(context).exportService
        .shareText(text, title: 'Moodly report');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          shared ? 'Report ready to share.' : 'Sharing is unavailable here.',
        ),
      ),
    );
  }

  Future<void> _delete(MoodReport report) async {
    await AppServices.of(context).reportService.deleteReport(report.id!);
    await _loadHistory();
    if (_report?.id == report.id && mounted) {
      setState(() => _report = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text('Your reports', style: theme.textTheme.headlineLarge),
            const SizedBox(height: 6),
            Text(
              'Weekly and monthly summaries computed from your actual '
              'check-ins — nothing is invented. Reports stay on this device '
              'and can be shared any time.',
              style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 20),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: MoodReport.kindWeekly,
                  label: Text('Weekly'),
                ),
                ButtonSegment(
                  value: MoodReport.kindMonthly,
                  label: Text('Monthly'),
                ),
              ],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => setState(() {
                _kind = selection.first;
                _report = null;
                _error = null;
              }),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _generate,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : const Icon(Icons.summarize_rounded),
                label: Text(
                  _kind == MoodReport.kindWeekly
                      ? 'Generate this week’s report'
                      : 'Generate this month’s report',
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            if (_report != null) ...[
              const SizedBox(height: 24),
              ReportDetailView(
                report: _report!,
                onShare: () => _share(_report!),
              ),
            ],
            if (_history.isNotEmpty) ...[
              const SizedBox(height: 28),
              const SectionHeader(title: 'Report history'),
              ..._history.map(
                (report) => AppCard(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      report.kind == MoodReport.kindWeekly
                          ? Icons.view_week_rounded
                          : Icons.calendar_month_rounded,
                      color: AppColors.primary,
                    ),
                    title: Text(report.periodLabel),
                    subtitle: Text(
                      report.isAiGenerated
                          ? 'AI summary · saved ${Formatters.mediumDate(report.createdAt)}'
                          : 'Local summary · saved ${Formatters.mediumDate(report.createdAt)}',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'view') setState(() => _report = report);
                        if (value == 'share') _share(report);
                        if (value == 'delete') _delete(report);
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'view', child: Text('View')),
                        PopupMenuItem(value: 'share', child: Text('Share')),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            'Delete',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      ],
                    ),
                    onTap: () => setState(() => _report = report),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// --- report rendering -------------------------------------------------------------

class ReportDetailView extends StatelessWidget {
  const ReportDetailView({super.key, required this.report, this.onShare});

  final MoodReport report;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = report.data['stats'];
    final statsMap = stats is Map
        ? Map<String, Object?>.from(stats)
        : const <String, Object?>{};
    final narrative = report.data['narrative']?.toString() ?? '';
    final rawQuestions = report.data['reflectionQuestions'];
    final questions = rawQuestions is List
        ? rawQuestions.map((q) => q.toString()).toList()
        : const <String>[];
    final comparison = report.data['comparison'];
    final trend = statsMap['trend'];
    final trendDirection = trend is Map ? trend['direction']?.toString() : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                report.kind == MoodReport.kindWeekly
                    ? 'Weekly report'
                    : 'Monthly report',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (onShare != null)
              IconButton(
                tooltip: 'Share report',
                onPressed: onShare,
                icon: const Icon(Icons.ios_share_rounded),
              ),
          ],
        ),
        Text(report.periodLabel, style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),

        // --- headline numbers -------------------------------------------------
        AppCard(
          child: Column(
            children: [
              _StatRow(
                label: 'Check-ins',
                value:
                    '${statsMap['totalCheckins'] ?? 0} of '
                    '${statsMap['spanDays'] ?? 0} days',
              ),
              _StatRow(
                label: 'Most logged mood',
                value: statsMap['mostCommonMood'] is String
                    ? Mood.fromStorageName(statsMap['mostCommonMood'] as String)
                          .label
                    : '—',
              ),
              _StatRow(
                label: 'Average energy',
                value: statsMap['averageEnergy'] is double
                    ? '${(statsMap['averageEnergy'] as double).toStringAsFixed(1)} / 5'
                    : '—',
              ),
              _StatRow(
                label: 'Mood trend',
                value: switch (trendDirection) {
                  'up' => '↑ Improving across the period',
                  'down' => '↓ Declining across the period',
                  'steady' => '→ Steady across the period',
                  _ => 'Not enough data',
                },
              ),
              if (report.kind == MoodReport.kindMonthly &&
                  comparison is Map) ...[
                _StatRow(
                  label: 'vs previous month',
                  value:
                      '${(((comparison['avgMoodDelta'] as num?) ?? 0) >= 0) ? '+' : ''}'
                      '${comparison['avgMoodDelta']} mood · '
                      '${comparison['avgEnergyDelta']} energy',
                ),
              ],
            ],
          ),
        ),

        // --- mood distribution -------------------------------------------------
        const SizedBox(height: 18),
        const SectionHeader(title: 'Mood distribution'),
        AppCard(
          child: _MoodDistribution(distribution: statsMap['moodDistribution']),
        ),

        // --- emotions ------------------------------------------------------------
        if (statsMap['mostCommonEmotions'] is List &&
            (statsMap['mostCommonEmotions'] as List).isNotEmpty) ...[
          const SizedBox(height: 18),
          const SectionHeader(title: 'Most common emotions'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: (statsMap['mostCommonEmotions'] as List)
                .map((raw) {
                  final map = raw is Map ? raw : const {};
                  final label = map['label']?.toString() ?? '';
                  final count = map['count']?.toString() ?? '';
                  if (label.isEmpty) return const SizedBox.shrink();
                  return Chip(label: Text('$label ×$count'));
                })
                .whereType<Widget>()
                .toList(),
          ),
        ],

        // --- narrative ------------------------------------------------------------
        const SizedBox(height: 18),
        SectionHeader(title: report.isAiGenerated ? 'AI summary' : 'Summary'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                narrative,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.65),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    report.isAiGenerated
                        ? Icons.auto_awesome_outlined
                        : Icons.handyman_outlined,
                    size: 15,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      report.isAiGenerated
                          ? 'Generated by AI from your statistics only — may be '
                                'inaccurate. Not medical advice.'
                          : 'Generated locally from your statistics (no AI).',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // --- questions ------------------------------------------------------------
        if (questions.isNotEmpty) ...[
          const SizedBox(height: 18),
          const SectionHeader(title: 'Reflection questions'),
          ...questions.map(
            (q) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.question_answer_rounded,
                    color: AppColors.primary,
                  ),
                  title: Text(q, style: theme.textTheme.bodyMedium),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        AppSection(
          child: Text(
            'All numbers come from your saved check-ins. Reports never contain '
            'journal text and are not a health assessment.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoodDistribution extends StatelessWidget {
  const _MoodDistribution({required this.distribution});

  final Object? distribution;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final map = distribution is Map
        ? Map<String, Object?>.from(distribution as Map)
        : const <String, Object?>{};
    final total = map.values.fold<int>(0, (sum, v) {
      final n = v is num ? v.toInt() : 0;
      return sum + n;
    });
    if (total == 0) {
      return Text(
        'No check-ins in this period.',
        style: theme.textTheme.bodySmall,
      );
    }
    final entries = map.entries.toList()
      ..sort(
        (a, b) => ((b.value as num?) ?? 0).compareTo((a.value as num?) ?? 0),
      );
    return Column(
      children: entries.map((entry) {
        final mood = Mood.fromStorageName(entry.key);
        final count = (entry.value as num?)?.toInt() ?? 0;
        final fraction = count / total;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              SizedBox(
                width: 74,
                child: Text(
                  mood.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: mood.color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 10,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(mood.color),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 64,
                child: Text(
                  '$count (${(fraction * 100).round()}%)',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// Plain-text rendering used for sharing.
class ReportTextRenderer {
  ReportTextRenderer._();

  static String render(MoodReport report) {
    final stats = report.data['stats'];
    final statsMap = stats is Map
        ? Map<String, Object?>.from(stats)
        : const <String, Object?>{};
    final narrative = report.data['narrative']?.toString() ?? '';
    final rawQuestions = report.data['reflectionQuestions'];
    final questions = rawQuestions is List
        ? rawQuestions.map((q) => q.toString()).toList()
        : const <String>[];

    final buffer = StringBuffer()
      ..writeln('MOODLY — ${report.kind.toUpperCase()} REPORT')
      ..writeln(report.periodLabel)
      ..writeln('')
      ..writeln('Check-ins: ${statsMap['totalCheckins'] ?? 0}')
      ..writeln('Most logged mood: ${statsMap['mostCommonMood'] ?? '—'}')
      ..writeln('Average energy: ${statsMap['averageEnergy'] ?? '—'} / 5')
      ..writeln('')
      ..writeln(narrative)
      ..writeln('');
    if (questions.isNotEmpty) {
      buffer.writeln('Reflection questions:');
      for (final q in questions) {
        buffer.writeln(' • $q');
      }
      buffer.writeln('');
    }
    buffer.writeln(
      report.isAiGenerated
          ? 'AI summary from statistics only — may be inaccurate.'
          : 'Generated locally from your statistics.',
    );
    return buffer.toString();
  }
}
