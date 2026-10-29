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
    Color(0xFF2E9E6B),
    Icons.wb_sunny_rounded,
  ),
  good('good', 'Good', 'Pretty well', 4, Color(0xFF4C8DF6), Icons.mood_rounded),
  okay(
    'okay',
    'Okay',
    'Getting by',
    3,
    Color(0xFFD9A22B),
    Icons.sentiment_neutral_rounded,
  ),
  low(
    'low',
    'Low',
    'A bit off',
    2,
    Color(0xFFE07A5F),
    Icons.sentiment_dissatisfied_rounded,
  ),
  terrible(
    'terrible',
    'Terrible',
    'Really rough',
    1,
    Color(0xFFC94F6C),
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
  Color get tint => color.withValues(alpha: 0.14);

  /// Resolves a persisted name, falling back to [fallback] for unknown values
  /// (e.g. entries written by a future app version).
  static Mood fromStorageName(String? name, {Mood fallback = Mood.okay}) {
    for (final mood in Mood.values) {
      if (mood.storageName == name) return mood;
    }
    return fallback;
  }
}
