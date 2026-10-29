import 'package:flutter/material.dart';

import '../../app.dart';
import '../calendar/calendar_screen.dart';
import '../home/home_screen.dart';
import '../insights/insights_screen.dart';
import '../journal/journal_screen.dart';
import '../settings/settings_screen.dart';

/// Bottom navigation host for the five Moodly tabs. Tabs are kept alive in an
/// [IndexedStack] and refreshed when re-selected so data is always current.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();
  final GlobalKey<CalendarScreenState> _calendarKey =
      GlobalKey<CalendarScreenState>();
  final GlobalKey<JournalScreenState> _journalKey =
      GlobalKey<JournalScreenState>();
  final GlobalKey<InsightsScreenState> _insightsKey =
      GlobalKey<InsightsScreenState>();
  final GlobalKey<SettingsScreenState> _settingsKey =
      GlobalKey<SettingsScreenState>();

  void _select(int index) {
    if (index == _index) {
      _refreshTab(index);
      return;
    }
    setState(() => _index = index);
    _refreshTab(index);
  }

  void _refreshTab(int index) {
    switch (index) {
      case 0:
        _homeKey.currentState?.refresh();
      case 1:
        _calendarKey.currentState?.refresh();
      case 2:
        _journalKey.currentState?.refresh();
      case 3:
        _insightsKey.currentState?.refresh();
      case 4:
        _settingsKey.currentState?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppServices.of(context);
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(key: _homeKey, onOpenTab: _select),
          CalendarScreen(key: _calendarKey),
          JournalScreen(key: _journalKey),
          InsightsScreen(key: _insightsKey),
          SettingsScreen(
            key: _settingsKey,
            settings: settings.settingsRepository,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Calendar',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book_rounded),
            label: 'Journal',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights_rounded),
            label: 'Insights',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
