import 'dart:convert';

import '../core/utils/date_utils.dart';

/// A saved weekly or monthly mood report (Phase 3).
///
/// The statistics are always computed from the user's own saved records. The
/// narrative is produced by local rules or — when the user is signed in and
/// AI processing consent is given — by the AI backend from the same
/// aggregates (journal text is never sent for reports).
class MoodReport {
  const MoodReport({
    this.id,
    required this.kind,
    required this.periodStart,
    required this.periodEnd,
    required this.periodLabel,
    required this.data,
    this.narrativeSource = 'local_rules',
    required this.createdAt,
  });

  static const String kindWeekly = 'weekly';
  static const String kindMonthly = 'monthly';

  final int? id;

  /// [kindWeekly] or [kindMonthly].
  final String kind;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String periodLabel;

  /// Structured statistics (see ReportService). Never contains journal text.
  final Map<String, Object?> data;

  /// `local_rules` or `ai:<provider>`.
  final String narrativeSource;

  final DateTime createdAt;

  bool get isAiGenerated => narrativeSource != 'local_rules';

  MoodReport copyWith({
    int? id,
    String? kind,
    DateTime? periodStart,
    DateTime? periodEnd,
    String? periodLabel,
    Map<String, Object?>? data,
    String? narrativeSource,
    DateTime? createdAt,
  }) {
    return MoodReport(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      periodStart: periodStart ?? this.periodStart,
      periodEnd: periodEnd ?? this.periodEnd,
      periodLabel: periodLabel ?? this.periodLabel,
      data: data ?? this.data,
      narrativeSource: narrativeSource ?? this.narrativeSource,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'kind': kind,
    'period_start': AppDates.dateKey(periodStart),
    'period_end': AppDates.dateKey(periodEnd),
    'period_label': periodLabel,
    'data': jsonEncode(data),
    'narrative_source': narrativeSource,
    'created_at': createdAt.toUtc().millisecondsSinceEpoch,
  };

  factory MoodReport.fromMap(Map<String, Object?> map) {
    final raw = map['data'];
    Map<String, Object?> decoded = const {};
    if (raw is String && raw.isNotEmpty) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is Map<String, Object?>) decoded = parsed;
      } on FormatException {
        decoded = const {};
      }
    }
    return MoodReport(
      id: map['id'] as int?,
      kind: map['kind'] as String,
      periodStart: AppDates.parseDateKey(map['period_start'] as String),
      periodEnd: AppDates.parseDateKey(map['period_end'] as String),
      periodLabel: map['period_label'] as String,
      data: decoded,
      narrativeSource: (map['narrative_source'] as String?) ?? 'local_rules',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['created_at'] as num?)?.toInt() ?? 0,
        isUtc: true,
      ).toLocal(),
    );
  }
}
