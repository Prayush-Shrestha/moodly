import 'package:flutter/material.dart';

/// Energy level selector (1–5) with a live descriptor so the chosen value is
/// always clearly shown.
class EnergySelector extends StatelessWidget {
  const EnergySelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// Current level, 1–5.
  final int value;
  final ValueChanged<int> onChanged;

  static const List<String> levelLabels = [
    'Drained',
    'Low',
    'Moderate',
    'High',
    'Energized',
  ];

  String get labelForValue => levelLabels[value - 1];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<int>(
          segments: [
            for (var i = 1; i <= 5; i++)
              ButtonSegment<int>(
                value: i,
                label: Text('$i', semanticsLabel: 'Energy level $i'),
                tooltip: levelLabels[i - 1],
              ),
          ],
          selected: {value},
          onSelectionChanged: (selection) => onChanged(selection.first),
          showSelectedIcon: false,
          multiSelectionEnabled: false,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(
              Icons.bolt_rounded,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              labelForValue,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text('Level $value of 5', style: theme.textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}
