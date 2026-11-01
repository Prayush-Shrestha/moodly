import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodly/app.dart';
import 'package:moodly/core/database/app_database.dart';
import 'package:moodly/core/theme/app_colors.dart';
import 'package:moodly/core/theme/app_theme.dart';
import 'package:moodly/core/utils/date_utils.dart';
import 'package:moodly/features/calendar/mood_day_cell.dart';
import 'package:moodly/models/mood.dart';
import 'package:moodly/models/mood_entry.dart';
import 'package:moodly/repositories/mood_repository.dart';
import 'package:moodly/repositories/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/test_harness.dart';

void main() {
  setupSqfliteFfiForTests();

  Future<void> settle(WidgetTester tester, {int pumps = 100}) async {
    for (var i = 0; i < pumps; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpApp(WidgetTester tester, AppDatabase database) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsRepository.load();
    await tester.pumpWidget(
      MoodlyApp(
        settingsRepository: settings,
        database: database,
        splashMinDisplay: Duration.zero,
      ),
    );
    await settle(tester);
    expect(find.text('Moodly'), findsNothing);
  }

  Future<void> openCalendar(WidgetTester tester) async {
    final tab = find.widgetWithText(NavigationDestination, 'Calendar');
    await tester.ensureVisible(tab);
    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(tab);
    await settle(tester);
  }

  Future<void> pumpCell(WidgetTester tester, MoodDayCell cell) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(child: SizedBox(width: 64, height: 64, child: cell)),
        ),
      ),
    );
  }

  BoxDecoration cellDecoration(WidgetTester tester) {
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(MoodDayCell),
            matching: find.byType(Container),
          )
          .first,
    );
    return container.decoration! as BoxDecoration;
  }

  group(
    'MoodDayCell shows the date and the saved mood emoji in one circle',
    () {
      testWidgets('October 31 + Good 😊', (tester) async {
        await pumpCell(
          tester,
          MoodDayCell(
            day: DateTime(2026, 10, 31),
            mood: Mood.good,
            isSelected: true,
          ),
        );

        final cell = find.byType(MoodDayCell);
        expect(
          find.descendant(of: cell, matching: find.text('31')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: cell, matching: find.text('😊')),
          findsOneWidget,
        );
        expect(cellDecoration(tester).color, AppColors.primary);
        expect(cellDecoration(tester).shape, BoxShape.circle);
      });

      testWidgets('November 1 + Low 😢', (tester) async {
        await pumpCell(
          tester,
          MoodDayCell(
            day: DateTime(2026, 11, 1),
            mood: Mood.low,
            isSelected: true,
          ),
        );

        final cell = find.byType(MoodDayCell);
        expect(
          find.descendant(of: cell, matching: find.text('1')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: cell, matching: find.text('😢')),
          findsOneWidget,
        );
        expect(cellDecoration(tester).color, AppColors.primary);
      });

      testWidgets('a date without a mood contains only its number', (
        tester,
      ) async {
        await pumpCell(
          tester,
          MoodDayCell(day: DateTime(2026, 10, 30), isSelected: true),
        );

        final cell = find.byType(MoodDayCell);
        final texts = find.descendant(of: cell, matching: find.byType(Text));
        expect(texts, findsOneWidget);
        expect(tester.widget<Text>(texts).data, '30');
        expect(find.text('😊'), findsNothing);
        expect(find.text('😢'), findsNothing);
      });

      testWidgets('unselected mood days keep the number and a subtle emoji', (
        tester,
      ) async {
        await pumpCell(
          tester,
          MoodDayCell(day: DateTime(2026, 10, 31), mood: Mood.good),
        );

        final cell = find.byType(MoodDayCell);
        expect(
          find.descendant(of: cell, matching: find.text('31')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: cell, matching: find.text('😊')),
          findsOneWidget,
        );
        expect(cellDecoration(tester).color, Mood.good.tint);
      });
    },
  );

  group('Calendar integration', () {
    testWidgets(
      'loads emojis from SQLite, updates after an edit and survives restart',
      (tester) async {
        // The app must be pumped before seeding: the in-memory FFI database
        // completes its futures while the test's fake clock is advanced.
        final database = inMemoryDatabase();
        await pumpApp(tester, database);

        final today = AppDates.dateOnly(DateTime.now());
        final repository = MoodRepository(database);
        await repository.save(
          MoodEntry(date: today, mood: Mood.good, energy: 3),
        );
        await openCalendar(tester);

        final todayCell = find.byKey(
          ValueKey('calendar-day-${AppDates.dateKey(today)}'),
        );
        expect(todayCell, findsOneWidget);
        expect(
          find.descendant(of: todayCell, matching: find.text('${today.day}')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: todayCell, matching: find.text('😊')),
          findsOneWidget,
        );

        // A different day in the current month has no saved mood.
        final noMoodDay = DateTime(
          today.year,
          today.month,
          today.day == 1 ? 2 : 1,
        );
        final noMoodCell = find.byKey(
          ValueKey('calendar-day-${AppDates.dateKey(noMoodDay)}'),
        );
        expect(noMoodCell, findsOneWidget);
        expect(
          find.descendant(of: noMoodCell, matching: find.byType(Text)),
          findsOneWidget,
        );

        // Changing months and returning must preserve the date/mood mapping.
        await tester.tap(find.byIcon(Icons.chevron_right_rounded));
        await settle(tester);
        await tester.tap(find.byIcon(Icons.chevron_left_rounded));
        await settle(tester);
        expect(
          find.descendant(of: todayCell, matching: find.text('😊')),
          findsOneWidget,
        );

        // Editing the saved mood updates the emoji in the same circle.
        final editButton = find.widgetWithText(OutlinedButton, 'Edit');
        await tester.ensureVisible(editButton);
        await tester.pump(const Duration(milliseconds: 30));
        await tester.tap(editButton);
        await settle(tester);

        await tester.tap(find.text('Low'));
        await settle(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
        await settle(tester);

        expect(
          find.descendant(of: todayCell, matching: find.text('😢')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: todayCell, matching: find.text('😊')),
          findsNothing,
        );
        expect((await repository.getAll()).single.mood, Mood.low);

        // Restart the app against the same SQLite connection: the reloaded
        // entry must show its edited emoji again.
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await pumpApp(tester, database);
        await openCalendar(tester);

        expect(
          find.descendant(of: todayCell, matching: find.text('😢')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: todayCell, matching: find.text('${today.day}')),
          findsOneWidget,
        );
      },
    );

    test(
      'a saved emoji survives closing and reopening the SQLite file',
      () async {
        final env = fileDatabase();
        addTearDown(env.cleanup);
        final day = DateTime(2026, 10, 31);

        await MoodRepository(env.database)
            .save(MoodEntry(date: day, mood: Mood.good, energy: 3));
        await env.database.close();

        final reopened = reopenDatabaseAt(env.path);
        addTearDown(reopened.database.close);
        final saved = (await MoodRepository(reopened.database).getByDate(day))!;
        expect(saved.mood, Mood.good);
        expect(saved.mood.emoji, '😊');

        // Editing the mood persists the new emoji, too.
        await MoodRepository(reopened.database)
            .save(MoodEntry(date: day, mood: Mood.low, energy: 3));
        await reopened.database.close();

        final again = reopenDatabaseAt(env.path);
        addTearDown(again.database.close);
        final edited = (await MoodRepository(again.database).getByDate(day))!;
        expect(edited.mood, Mood.low);
        expect(edited.mood.emoji, '😢');
      },
    );
  });
}
