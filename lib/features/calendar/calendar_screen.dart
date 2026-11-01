import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../app.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/formatters.dart';
import '../../models/mood_entry.dart';
import '../../widgets/app_card.dart';
import '../../widgets/mood_display.dart';
import '../../widgets/status_views.dart';
import '../check_in/mood_check_in_screen.dart';
import 'mood_day_cell.dart';

/// Month view with mood indicators; selecting a day shows its entry and
/// allows editing or creating a check-in for that day.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => CalendarScreenState();
}

class CalendarScreenState extends State<CalendarScreen> {
  Map<String, MoodEntry> _byDate = {};
  bool _loading = true;
  String? _error;
  DateTime _focusedDay = AppDates.dateOnly(DateTime.now());
  DateTime _selectedDay = AppDates.dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    refresh();
  }

  /// Called by the shell when this tab is (re)selected.
  Future<void> refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await AppServices.of(context).moodRepository.getAll();
      if (!mounted) return;
      setState(() {
        _byDate = {
          for (final entry in all) AppDates.dateKey(entry.date): entry,
        };
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not read your saved moods.';
      });
    }
  }

  Future<void> _openCheckIn(DateTime date) async {
    final existing = _byDate[AppDates.dateKey(date)];
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MoodCheckInScreen(existing: existing, date: date),
      ),
    );
    if (saved == true && mounted) refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      body: SafeArea(
        child: _loading
            ? const LoadingState(label: 'Loading your month…')
            : _error != null
            ? ErrorState(message: _error!, onRetry: refresh)
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  _buildCalendar(theme),
                  const SizedBox(height: 16),
                  _buildSelectedDay(theme),
                ],
              ),
      ),
    );
  }

  Widget _buildCalendar(ThemeData theme) {
    return TableCalendar<MoodEntry>(
      locale: 'en_US',
      firstDay: DateTime(2020, 1, 1),
      lastDay: DateTime(2035, 12, 31),
      focusedDay: _focusedDay,
      selectedDayPredicate: (day) => AppDates.isSameDay(day, _selectedDay),
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = AppDates.dateOnly(selectedDay);
          _focusedDay = AppDates.dateOnly(focusedDay);
        });
      },
      onPageChanged: (focusedDay) {
        setState(() => _focusedDay = AppDates.dateOnly(focusedDay));
      },
      calendarFormat: CalendarFormat.month,
      availableCalendarFormats: const {CalendarFormat.month: 'Month'},
      startingDayOfWeek: StartingDayOfWeek.monday,
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle: theme.textTheme.titleLarge!.copyWith(
          fontWeight: FontWeight.w700,
        ),
        leftChevronIcon: Icon(
          Icons.chevron_left_rounded,
          color: theme.colorScheme.onSurface,
        ),
        rightChevronIcon: Icon(
          Icons.chevron_right_rounded,
          color: theme.colorScheme.onSurface,
        ),
        headerPadding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle: theme.textTheme.bodySmall!.copyWith(
          fontWeight: FontWeight.w600,
        ),
        weekendStyle: theme.textTheme.bodySmall!.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      calendarStyle: CalendarStyle(
        todayDecoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.10),
          shape: BoxShape.circle,
        ),
        todayTextStyle: TextStyle(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        selectedDecoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
        selectedTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        defaultTextStyle: TextStyle(color: theme.colorScheme.onSurface),
        weekendTextStyle: TextStyle(color: theme.colorScheme.onSurface),
        outsideTextStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        cellMargin: const EdgeInsets.all(6),
      ),
      calendarBuilders: CalendarBuilders<MoodEntry>(
        selectedBuilder: (context, day, _) =>
            _buildDayCell(day, selected: true),
        todayBuilder: (context, day, _) {
          if (AppDates.isSameDay(day, _selectedDay)) return null;
          return _buildDayCell(day, today: true);
        },
        // Every normal day uses the same cell so the date number always
        // remains visible. Mood days add the emoji inside the same circle.
        defaultBuilder: (context, day, _) => _buildDayCell(day),
      ),
    );
  }

  Widget _buildDayCell(
    DateTime day, {
    bool selected = false,
    bool today = false,
  }) {
    final entry = _byDate[AppDates.dateKey(day)];
    return MoodDayCell(
      key: ValueKey('calendar-day-${AppDates.dateKey(day)}'),
      day: day,
      mood: entry?.mood,
      isSelected: selected,
      isToday: today,
    );
  }

  Widget _buildSelectedDay(ThemeData theme) {
    final entry = _byDate[AppDates.dateKey(_selectedDay)];
    final isFuture = AppDates.isFuture(_selectedDay);
    final isSelectedToday = AppDates.isSameDay(_selectedDay, DateTime.now());

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isSelectedToday
                      ? 'Today · ${Formatters.mediumDate(_selectedDay)}'
                      : Formatters.fullDate(_selectedDay),
                  style: theme.textTheme.titleLarge,
                ),
              ),
              if (entry != null)
                OutlinedButton.icon(
                  onPressed: () => _openCheckIn(_selectedDay),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (entry != null)
            MoodEntryCard(entry: entry, showDate: false)
          else if (isFuture)
            Text(
              'Future days cannot be checked in yet.',
              style: theme.textTheme.bodySmall,
            )
          else
            EmptyState(
              icon: Icons.event_available_outlined,
              title: 'No check-in for this day',
              message: 'Record how this day felt to see it here and in your insights.',
              actionLabel: 'Check in for this day',
              onAction: () => _openCheckIn(_selectedDay),
            ),
        ],
      ),
    );
  }
}
