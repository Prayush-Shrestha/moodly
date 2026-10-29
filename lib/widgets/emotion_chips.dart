import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../models/emotion.dart';

/// Multi-select emotion tag chips with a calm two-tone treatment
/// (soft lavender for positive feelings, soft coral for difficult ones).
class EmotionChips extends StatelessWidget {
  const EmotionChips({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Set<Emotion> selected;
  final ValueChanged<Set<Emotion>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final emotion in Emotion.values)
          _EmotionChip(
            emotion: emotion,
            isSelected: selected.contains(emotion),
            onTap: () {
              final next = Set<Emotion>.of(selected);
              if (!next.remove(emotion)) next.add(emotion);
              onChanged(next);
            },
          ),
      ],
    );
  }
}

class _EmotionChip extends StatelessWidget {
  const _EmotionChip({
    required this.emotion,
    required this.isSelected,
    required this.onTap,
  });

  final Emotion emotion;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final positive = emotion.tone == EmotionTone.positive;
    final accent = positive ? AppColors.primary : AppColors.danger;
    final fill = isSelected
        ? accent.withValues(alpha: 0.12)
        : theme.colorScheme.surface;

    return Semantics(
      button: true,
      selected: isSelected,
      label: 'Emotion ${emotion.label}',
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isSelected ? accent : theme.colorScheme.outlineVariant,
            width: isSelected ? 1.6 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  emotion.icon,
                  size: 17,
                  color: isSelected
                      ? accent
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  emotion.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
