import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodly/app.dart';
import 'package:moodly/core/database/app_database.dart';
import 'package:moodly/features/privacy/privacy_screen.dart';
import 'package:moodly/repositories/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_harness.dart';

/// Widget smoke tests for the Phase 3 screens. Network calls fail fast in
/// tests (the HTTP binding returns 400), which exercises the honest
/// offline/error states rather than pretending AI or sync is available.
void main() {
  setupSqfliteFfiForTests();

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
    // Let the splash transition and initial futures settle. Indeterminate
    // spinners never settle, so pump a fixed number of frames.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Moodly'), findsNothing);
    return database;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> openFromSettings(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text('Settings'));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(find.text('Settings'));
    await settle(tester);
    // Long settings list: scroll the entry into view, then aim and tap.
    await tester.scrollUntilVisible(find.text(label), 300);
    await tester.ensureVisible(find.text(label));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text(label));
    await settle(tester);
  }

  testWidgets('settings lists the Phase 3 entries', (tester) async {
    await pumpApp(tester);

    await tester.ensureVisible(find.text('Settings'));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(find.text('Settings'));
    await settle(tester);

    expect(find.text('Account & sync'), findsOneWidget);
    // Scroll through the list to confirm every entry is reachable.
    for (final label in [
      'Account',
      'Cloud sync',
      'Reports',
      'Privacy & data',
    ]) {
      final finder = find.text(label);
      await tester.scrollUntilVisible(finder, 300);
      expect(finder, findsOneWidget);
    }
    final version = find.textContaining('Phase 3');
    await tester.scrollUntilVisible(version, 300);
    expect(version, findsOneWidget);
  });

  testWidgets('account screen shows the sign-in form without an account', (
    tester,
  ) async {
    await pumpApp(tester);
    await openFromSettings(tester, 'Account');

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    // Toggle to the registration form.
    expect(find.text('Create an account'), findsOneWidget);
    // The optional nature of accounts is stated upfront.
    expect(find.textContaining('optional'), findsWidgets);
  });

  testWidgets('privacy screen gates consents behind sign-in', (tester) async {
    await pumpApp(tester);
    await openFromSettings(tester, 'Privacy & data');

    expect(find.text('You are in control'), findsOneWidget);
    // Consent switches exist but are disabled without an account.
    final aiSwitch = find.ancestor(
      of: find.text('AI processing'),
      matching: find.byType(SwitchListTile),
    );
    expect(aiSwitch, findsOneWidget);
    expect(tester.widget<SwitchListTile>(aiSwitch).onChanged, isNull);
    // The transparency and disclaimer sections sit below the fold, so scroll
    // the privacy screen's own list (the settings list is also in the tree).
    final scrollable = find.descendant(
      of: find.byType(PrivacyScreen),
      matching: find.byType(Scrollable),
    );
    // Transparency section: what is stored where.
    final transparency = find.textContaining('stored where');
    await tester.scrollUntilVisible(transparency, 300, scrollable: scrollable);
    expect(transparency, findsOneWidget);
    final noTraining = find.textContaining('not used to train AI models');
    await tester.scrollUntilVisible(noTraining, 300, scrollable: scrollable);
    expect(noTraining, findsOneWidget);
    // AI disclaimer.
    final disclaimer = find.textContaining('not a medical or mental-health');
    await tester.scrollUntilVisible(disclaimer, 300, scrollable: scrollable);
    expect(disclaimer, findsOneWidget);
  });

  testWidgets('sync screen explains conflicts and stays disabled offline', (
    tester,
  ) async {
    await pumpApp(tester);
    await openFromSettings(tester, 'Cloud sync');

    expect(find.text('Sync your data'), findsOneWidget);
    expect(find.text('How conflicts are handled'), findsOneWidget);
    // Not signed in → sync-now is unavailable (never fakes activity).
    final syncButton = find.widgetWithText(FilledButton, 'Sync now');
    expect(syncButton, findsOneWidget);
    expect(tester.widget<FilledButton>(syncButton).onPressed, isNull);
    expect(find.text('Sign in to enable'), findsOneWidget);
  });

  testWidgets('reports screen generates an honest empty report offline', (
    tester,
  ) async {
    await pumpApp(tester);
    await openFromSettings(tester, 'Reports');

    expect(find.text('Your reports'), findsOneWidget);
    await tester.tap(find.text('Generate this week’s report'));
    await settle(tester);
    // The empty narrative must be honest about missing data.
    expect(find.textContaining('No check-ins were recorded'), findsOneWidget);
    // Local narrative is labelled as such.
    expect(find.textContaining('Generated locally'), findsOneWidget);
    // The disclaimer about what reports are not.
    expect(find.textContaining('not a health assessment'), findsOneWidget);
  });
}
