import 'package:flutter/material.dart';

import '../core/utils/formatters.dart';
import '../models/emotion.dart';
import '../models/mood.dart';
import '../models/mood_entry.dart';

/// Compact visual for a mood: colored dot + label + score-friendly icon.
class MoodBadge extends StatelessWidget {
  const MoodBadge({
    super.key,
    required this.mood,
    this.iconSize = 20,
    this.fontSize = 15,
  });

  final Mood mood;
  final double iconSize;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: iconSize + 8,
          height: iconSize + 8,
          decoration: BoxDecoration(color: mood.tint, shape: BoxShape.circle),
          child: Icon(mood.icon, size: iconSize, color: mood.color),
        ),
        const SizedBox(width: 8),
        Text(
          mood.label,
          style: theme.textTheme.titleMedium?.copyWith(fontSize: fontSize),
        ),
      ],
    );
  }
}

/// Five dots visualizing an energy level out of 5.
class EnergyDots extends StatelessWidget {
  const EnergyDots({super.key, required this.level, this.size = 8});

  final int level;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Energy $level out of 5',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Container(
              width: size,
              height: size,
              margin: EdgeInsets.only(right: i < 5 ? 3 : 0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i <= level
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// Emotion tags as compact, non-interactive chips (display only).
class EmotionTagList extends StatelessWidget {
  const EmotionTagList({super.key, required this.emotions, this.max = 6});

  final List<Emotion> emotions;
  final int max;

  @override
  Widget build(BuildContext context) {
    if (emotions.isEmpty) return const SizedBox.shrink();
    final shown = emotions.length <= max ? emotions : emotions.sublist(0, max);
    final overflow = emotions.length - shown.length;
    final theme = Theme.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final emotion in shown)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  emotion.icon,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(emotion.label, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        if (overflow > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('+$overflow', style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}

/// Full display card for a saved mood check-in (read-only).
class MoodEntryCard extends StatelessWidget {
  const MoodEntryCard({
    super.key,
    required this.entry,
    this.onTap,
    this.showDate = true,
  });

  final MoodEntry entry;
  final VoidCallback? onTap;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                MoodBadge(mood: entry.mood),
                const Spacer(),
                if (showDate)
                  Text(
                    Formatters.mediumDate(entry.date),
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text('Energy', style: theme.textTheme.bodySmall),
                const SizedBox(width: 8),
                EnergyDots(level: entry.energy),
              ],
            ),
            if (entry.emotions.isNotEmpty) ...[
              const SizedBox(height: 10),
              EmotionTagList(emotions: entry.emotions),
            ],
            if (entry.note != null && entry.note!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                entry.note!.trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
