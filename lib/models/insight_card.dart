import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// The kind of insight, used for icons and grouping.
enum InsightType { mood, energy, emotion, consistency, journal }

/// Qualitative confidence; rule-based insights start at `low`.
enum InsightConfidence { low, medium, high }

/// A single insight card shown on the AI Insights screen.
///
/// Every insight is backed by real stored data. [evidence] explains which
/// records the insight is based on. [confidence] is a qualitative, explainable
/// level — never a statistical guarantee.
class InsightCard {
  const InsightCard({
    required this.title,
    required this.description,
    required this.type,
    this.evidence,
    this.dateRangeStart,
    this.dateRangeEnd,
    this.dataPointCount = 0,
    this.confidence = InsightConfidence.low,
    this.isRuleBased = true,
  });

  final String title;
  final String description;
  final InsightType type;
  final String? evidence;
  final DateTime? dateRangeStart;
  final DateTime? dateRangeEnd;
  final int dataPointCount;
  final InsightConfidence confidence;
  final bool isRuleBased;

  /// Friendly label for the type, shown in the UI.
  String get typeLabel {
    switch (type) {
      case InsightType.mood:
        return 'Mood';
      case InsightType.energy:
        return 'Energy';
      case InsightType.emotion:
        return 'Emotions';
      case InsightType.consistency:
        return 'Consistency';
      case InsightType.journal:
        return 'Journal';
    }
  }

  /// Short confidence label for display.
  String get confidenceLabel {
    switch (confidence) {
      case InsightConfidence.high:
        return 'High confidence';
      case InsightConfidence.medium:
        return 'Medium confidence';
      case InsightConfidence.low:
        return 'Low confidence';
    }
  }

  /// Display color for the insight type.
  Color get typeColor {
    switch (type) {
      case InsightType.mood:
        return const Color(0xFF2E9E6B);
      case InsightType.energy:
        return const Color(0xFF4C8DF6);
      case InsightType.emotion:
        return const Color(0xFFD9A22B);
      case InsightType.consistency:
        return AppColors.primary;
      case InsightType.journal:
        return AppColors.danger;
    }
  }
}
