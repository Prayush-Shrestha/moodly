import 'package:flutter/material.dart';

/// Emotion tags a user can attach to a mood check-in.
enum Emotion {
  calm('calm', 'Calm', EmotionTone.positive, Icons.spa_outlined),
  happy(
    'happy',
    'Happy',
    EmotionTone.positive,
    Icons.sentiment_very_satisfied_outlined,
  ),
  excited(
    'excited',
    'Excited',
    EmotionTone.positive,
    Icons.auto_awesome_outlined,
  ),
  grateful(
    'grateful',
    'Grateful',
    EmotionTone.positive,
    Icons.favorite_outline,
  ),
  motivated(
    'motivated',
    'Motivated',
    EmotionTone.positive,
    Icons.emoji_objects_outlined,
  ),
  tired('tired', 'Tired', EmotionTone.difficult, Icons.battery_1_bar_outlined),
  stressed('stressed', 'Stressed', EmotionTone.difficult, Icons.bolt_outlined),
  anxious(
    'anxious',
    'Anxious',
    EmotionTone.difficult,
    Icons.warning_amber_outlined,
  ),
  sad('sad', 'Sad', EmotionTone.difficult, Icons.water_drop_outlined),
  angry(
    'angry',
    'Angry',
    EmotionTone.difficult,
    Icons.local_fire_department_outlined,
  );

  const Emotion(this.storageName, this.label, this.tone, this.icon);

  /// Stable identifier persisted in the database.
  final String storageName;
  final String label;
  final EmotionTone tone;
  final IconData icon;
}

/// Broad grouping used to tint emotion chips consistently.
enum EmotionTone { positive, difficult }

/// Converts a persisted comma-separated list (e.g. `calm,happy`) back into
/// [Emotion] values, skipping names this version doesn't recognise.
List<Emotion> parseEmotions(String? stored) {
  if (stored == null || stored.trim().isEmpty) return const [];
  final result = <Emotion>[];
  for (final raw in stored.split(',')) {
    final name = raw.trim();
    if (name.isEmpty) continue;
    for (final emotion in Emotion.values) {
      if (emotion.storageName == name) {
        result.add(emotion);
        break;
      }
    }
  }
  return result;
}

/// Serializes emotions in their canonical enum order for stable storage.
String serializeEmotions(List<Emotion> emotions) =>
    emotions.map((e) => e.storageName).join(',');
