import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodly/app.dart';
import 'package:moodly/core/database/app_database.dart';
import 'package:moodly/models/mood.dart';
import 'package:moodly/repositories/journal_repository.dart';
import 'package:moodly/repositories/mood_repository.dart';
import 'package:moodly/repositories/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/test_harness.dart';

void main() {
  setupSqfliteFfiForTests();

  /// Advance fake time by a fixed number of steps.
  ///
  /// We avoid [WidgetTester.pumpAndSettle] because the splash/loading spinners
  /// are indeterminate (they animate forever). A fixed count guarantees route
  /// transitions finish and every tab's in-isolate FFI SQLite futures drain —
  /// including those of offstage tabs in the [IndexedStack], so nothing is
  /// pending when the database is closed in teardown.
  Future<void> settle(WidgetTester tester, {int pumps = 60}) async {
    for (var i = 0; i < pumps; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<AppDatabase> pumpApp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsRepository.load();
    final database = inMemoryDatabase();
    await tester.pumpWidget(
      MoodlyApp(
        settingsRepository: settings,
        database: database,
        splashMinDisplay: Duration.zero,
      ),
    );
    await settle(tester);
    // Splash must be fully gone (its transition completes within the pumps
    // above) before assertions run.
    expect(find.text('Moodly'), findsNothing);
    return database;
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(finder);
    await settle(tester);
  }

  testWidgets(
    'home shows greeting, empty state and weekly summary on first launch',
    (tester) async {
      await pumpApp(tester);

      expect(find.text('No check-ins yet'), findsOneWidget);
      expect(find.text('Check in'), findsOneWidget);
      expect(find.text('This week'), findsOneWidget);
      expect(find.text('Recent check-ins'), findsOneWidget);
    },
  );

  testWidgets('full check-in flow persists one entry per day', (tester) async {
    final database = await pumpApp(tester);
    final repository = MoodRepository(database);

    // Start a check-in from the home hero card.
    await tapAndSettle(tester, find.text('Check in'));
    expect(find.text('How did this day feel?'), findsOneWidget);

    // Save is disabled until a mood is chosen.
    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save check-in'),
    );
    expect(saveButton.onPressed, isNull);

    // Select a mood, tag an emotion, set energy, add a note.
    await tapAndSettle(tester, find.text('Great'));
    await tapAndSettle(tester, find.text('Grateful'));
    await tapAndSettle(tester, find.text('4'));
    await tester.ensureVisible(find.byType(TextField));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.enterText(find.byType(TextField), 'A really nice day.');
    await tester.pump(const Duration(milliseconds: 30));

    await tapAndSettle(
      tester,
      find.widgetWithText(FilledButton, 'Save check-in'),
    );

    // Back on home, today's entry is shown.
    expect(find.text("Today's mood"), findsOneWidget);
    // The note appears on the home card and again in the recent list.
    expect(find.text('A really nice day.'), findsWidgets);

    final entries = await repository.getAll();
    expect(entries, hasLength(1));
    expect(entries.first.mood, Mood.great);
    expect(entries.first.energy, 4);
    expect(entries.first.note, 'A really nice day.');
  });

  testWidgets(
    'checking in twice on the same day edits instead of duplicating',
    (tester) async {
      final database = await pumpApp(tester);
      final repository = MoodRepository(database);

      await tapAndSettle(tester, find.text('Check in'));
      await tapAndSettle(tester, find.text('Good'));
      await tapAndSettle(
        tester,
        find.widgetWithText(FilledButton, 'Save check-in'),
      );
      expect(await repository.count(), 1);

      // Edit today's entry from the home card.
      await tapAndSettle(tester, find.text('Edit').first);
      expect(find.text('Edit check-in'), findsOneWidget);

      await tapAndSettle(tester, find.text('Low'));
      await tapAndSettle(
        tester,
        find.widgetWithText(FilledButton, 'Save changes'),
      );

      final entries = await repository.getAll();
      expect(entries, hasLength(1));
      expect(entries.first.mood, Mood.low);
    },
  );

  testWidgets('insights show an empty state before any entries exist', (
    tester,
  ) async {
    await pumpApp(tester);

    await tapAndSettle(tester, find.text('Insights'));
    expect(find.text('No insights yet'), findsOneWidget);
  });

  testWidgets('clear all data requires confirmation and empties the app', (
    tester,
  ) async {
    final database = await pumpApp(tester);
    final repository = MoodRepository(database);

    // Create a check-in first.
    await tapAndSettle(tester, find.text('Check in'));
    await tapAndSettle(tester, find.text('Okay'));
    await tapAndSettle(
      tester,
      find.widgetWithText(FilledButton, 'Save check-in'),
    );
    expect(await repository.count(), 1);

    // Settings → clear data → cancel keeps data.
    await tapAndSettle(tester, find.text('Settings'));
    await tapAndSettle(tester, find.text('Clear all data'));
    await tapAndSettle(tester, find.text('Cancel'));
    expect(await repository.count(), 1);

    // Confirm deletes everything.
    await tapAndSettle(tester, find.text('Clear all data'));
    await tapAndSettle(tester, find.text('Delete everything'));
    expect(await repository.count(), 0);
  });

  testWidgets('journal flow allows creating, viewing and searching entries', (
    tester,
  ) async {
    final database = await pumpApp(tester);
    final journalRepo = JournalRepository(database);

    await tapAndSettle(tester, find.text('Journal'));
    expect(find.text('Your journal is empty'), findsOneWidget);

    await tapAndSettle(tester, find.text('New entry'));
    expect(find.text('Title (optional)'), findsOneWidget);

    await tapAndSettle(tester, find.text('Save entry'));
    expect(find.text('Write something before saving.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Title (optional)'),
      'My Peaceful Morning',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'What is on your mind?'),
      'Had a calm tea and reflected on priorities.',
    );
    await tapAndSettle(tester, find.text('Save entry'));

    expect(find.text('My Peaceful Morning'), findsOneWidget);
    expect(await journalRepo.count(), 1);

    final searchField = find.widgetWithText(TextField, 'Search your entries…');
    await tester.enterText(searchField, 'Peaceful');
    await settle(tester);
    expect(find.text('My Peaceful Morning'), findsOneWidget);

    await tester.enterText(searchField, 'NonexistentSearch');
    await settle(tester);
    expect(find.text('No matches'), findsOneWidget);
  });

  testWidgets('calendar tab displays current month and day card', (
    tester,
  ) async {
    await pumpApp(tester);

    await tapAndSettle(
      tester,
      find.widgetWithText(NavigationDestination, 'Calendar'),
    );
    expect(find.text('Calendar'), findsWidgets);
    expect(find.textContaining('Today'), findsWidgets);
  });

  testWidgets('settings tab allows toggling theme mode', (tester) async {
    await pumpApp(tester);

    await tapAndSettle(tester, find.text('Settings'));
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);

    await tapAndSettle(tester, find.text('Dark'));
    expect(find.text('Dark'), findsOneWidget);
  });
}
