import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/mood.dart';

/// A single day cell in the month grid.
///
/// The date number is always visible. When a mood is saved for the day, its
/// emoji is drawn directly underneath the number — inside the same circular
/// indicator. Nothing is rendered outside the circle.
class MoodDayCell extends StatelessWidget {
  const MoodDayCell({
    super.key,
    required this.day,
    this.mood,
    this.isSelected = false,
    this.isToday = false,
  });

  final DateTime day;
  final Mood? mood;
  final bool isSelected;
  final bool isToday;

  /// Slightly smaller than the calendar's default so both the number and the
  /// emoji fit comfortably in the same circle.
  static const EdgeInsets _margin = EdgeInsets.all(4);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mood = this.mood;

    final Color? background;
    if (isSelected) {
      background = AppColors.primary;
    } else if (mood != null) {
      background = mood.tint;
    } else if (isToday) {
      background = AppColors.primary.withValues(alpha: 0.10);
    } else {
      background = null;
    }

    return Container(
      margin: _margin,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: background,
        border: isToday && !isSelected
            ? Border.all(
                color: AppColors.primary.withValues(alpha: 0.35),
                width: 1.5,
              )
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${day.day}',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 13,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: isSelected
                      ? Colors.white
                      : theme.colorScheme.onSurface,
                ),
              ),
              if (mood != null)
                Opacity(
                  opacity: isSelected ? 1 : 0.85,
                  child: Text(
                    mood.emoji,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 12, height: 1),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
