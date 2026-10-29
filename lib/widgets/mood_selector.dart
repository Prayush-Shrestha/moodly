import 'package:flutter/material.dart';

import '../models/mood.dart';

/// Horizontal selector for the five moods.
///
/// Each option is a >=72dp tile with an icon, label and check badge when
/// selected. Selection is announced via Semantics, and color is always
/// accompanied by an icon so the meaning never relies on color alone.
class MoodSelector extends StatelessWidget {
  const MoodSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final Mood? selected;
  final ValueChanged<Mood> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = (constraints.maxWidth - 4 * 8) / 5;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mood in Mood.values)
              SizedBox(
                width: tileWidth.clamp(58.0, 92.0),
                child: _MoodTile(
                  mood: mood,
                  selected: selected == mood,
                  onTap: () => onSelected(mood),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MoodTile extends StatelessWidget {
  const _MoodTile({
    required this.mood,
    required this.selected,
    required this.onTap,
  });

  final Mood mood;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = selected
        ? mood.color
        : theme.colorScheme.outlineVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Mood ${mood.label}',
      child: Material(
        color: selected ? mood.tint : theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: borderColor, width: selected ? 2 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(mood.icon, size: 28, color: mood.color),
                    if (selected)
                      Positioned(
                        right: -6,
                        top: -4,
                        child: Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: mood.color,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  mood.label,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
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
