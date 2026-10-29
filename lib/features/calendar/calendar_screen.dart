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
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
                children: [
                  _buildCalendar(theme),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const .symmetric(horizontal: 8),
                    child: _buildSelectedDay(theme),
                  ),
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
      eventLoader: (day) {
        final entry = _byDate[AppDates.dateKey(day)];
        return entry == null ? const [] : [entry];
      },
      calendarFormat: CalendarFormat.month,
      availableCalendarFormats: const {CalendarFormat.month: 'Month'},
      startingDayOfWeek: StartingDayOfWeek.monday,
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle: theme.textTheme.titleMedium!,
        leftChevronIcon: Icon(
          Icons.chevron_left_rounded,
          color: theme.colorScheme.onSurface,
        ),
        rightChevronIcon: Icon(
          Icons.chevron_right_rounded,
          color: theme.colorScheme.onSurface,
        ),
        headerPadding: const EdgeInsets.symmetric(vertical: 10),
      ),
      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle: theme.textTheme.bodySmall!,
        weekendStyle: theme.textTheme.bodySmall!,
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
        selectedDecoration: const BoxDecoration(
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
        cellMargin: const EdgeInsets.all(5),
      ),
      calendarBuilders: CalendarBuilders<MoodEntry>(
        singleMarkerBuilder: (context, day, entry) => Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppDates.isSameDay(day, _selectedDay)
                ? Colors.white
                : entry.mood.color,
          ),
        ),
        selectedBuilder: (context, day, _) {
          return Container(
            margin: const EdgeInsets.all(5),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary,
            ),
            alignment: Alignment.center,
            child: Text(
              '${day.day}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        },
        todayBuilder: (context, day, _) {
          final entry = _byDate[AppDates.dateKey(day)];
          final isSelected = AppDates.isSameDay(day, _selectedDay);
          if (isSelected) return null;
          return Container(
            margin: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: entry != null
                  ? entry.mood.tint
                  : AppColors.primary.withValues(alpha: 0.10),
              border: Border.all(color: AppColors.primary, width: 1.6),
            ),
            alignment: Alignment.center,
            child: Text(
              '${day.day}',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        },
        // Show a faint tint on days with an entry so the month reads at a glance.
        defaultBuilder: (context, day, _) {
          final entry = _byDate[AppDates.dateKey(day)];
          if (entry == null) return null;
          return Container(
            margin: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: entry.mood.tint,
            ),
            alignment: Alignment.center,
            child: Text(
              '${day.day}',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        },
      ),
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
                  style: theme.textTheme.titleMedium,
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
          const SizedBox(height: 12),
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
