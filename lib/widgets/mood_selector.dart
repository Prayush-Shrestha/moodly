import 'package:flutter/material.dart';

import '../models/mood.dart';

/// Horizontal selector for the five moods.
///
/// Each option is a generously sized tile with an icon, label, and selected
/// state. Selection is announced via Semantics, and color is always
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
                width: tileWidth.clamp(64.0, 100.0),
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
    final isLight = theme.brightness == Brightness.light;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Mood ${mood.label}',
      child: Material(
        color: selected
            ? mood.color.withValues(alpha: isLight ? 0.14 : 0.22)
            : theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected ? mood.color : theme.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(mood.icon, size: 30, color: mood.color),
                    if (selected)
                      Positioned(
                        right: -6,
                        top: -4,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: mood.color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.colorScheme.surface,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  mood.label,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected
                        ? mood.color
                        : theme.colorScheme.onSurfaceVariant,
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
