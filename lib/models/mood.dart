import 'package:flutter/material.dart';

/// The five tracked moods, ordered from best (great) to worst (terrible).
///
/// [score] (1–5) powers averages and trends; [color] is used for dots, chart
/// bars and selection rings. Label text always stays in the theme's ink color
/// so contrast remains accessible — color is carried by icons and shapes.
enum Mood {
  great(
    'great',
    'Great',
    'Feeling fantastic',
    5,
    MoodColors.great,
    Icons.wb_sunny_rounded,
  ),
  good('good', 'Good', 'Pretty well', 4, MoodColors.good, Icons.mood_rounded),
  okay(
    'okay',
    'Okay',
    'Getting by',
    3,
    MoodColors.okay,
    Icons.sentiment_neutral_rounded,
  ),
  low(
    'low',
    'Low',
    'A bit off',
    2,
    MoodColors.low,
    Icons.sentiment_dissatisfied_rounded,
  ),
  terrible(
    'terrible',
    'Terrible',
    'Really rough',
    1,
    MoodColors.terrible,
    Icons.sentiment_very_dissatisfied_rounded,
  );

  const Mood(
    this.storageName,
    this.label,
    this.subtitle,
    this.score,
    this.color,
    this.icon,
  );

  /// Stable identifier persisted in the database.
  final String storageName;
  final String label;
  final String subtitle;

  /// Numeric value (1 = terrible … 5 = great) used for analytics.
  final int score;
  final Color color;
  final IconData icon;

  /// Gentle tint used for selected tiles/chips while keeping text readable.
  Color get tint => color.withValues(alpha: 0.12);

  /// Soft border color used for unselected mood tiles.
  Color get borderColor => color.withValues(alpha: 0.35);

  /// Resolves a persisted name, falling back to [fallback] for unknown values
  /// (e.g. entries written by a future app version).
  static Mood fromStorageName(String? name, {Mood fallback = Mood.okay}) {
    for (final mood in Mood.values) {
      if (mood.storageName == name) return mood;
    }
    return fallback;
  }
}

/// Gentle, brand-aligned mood colors used across the app.
abstract final class MoodColors {
  /// Great — gentle mint green.
  static const Color great = Color(0xFF5DBFA0);

  /// Good — gentle periwinkle blue.
  static const Color good = Color(0xFF6E94F2);

  /// Okay — gentle golden amber.
  static const Color okay = Color(0xFFE8C96B);

  /// Low — gentle warm orange.
  static const Color low = Color(0xFFE09A6B);

  /// Terrible — gentle rose.
  static const Color terrible = Color(0xFFC97A8C);
}
