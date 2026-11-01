import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moodly/core/database/app_database.dart';
import 'package:moodly/core/network/api_client.dart';
import 'package:moodly/core/network/token_store.dart';
import 'package:moodly/models/mood.dart';
import 'package:moodly/models/mood_entry.dart';
import 'package:moodly/repositories/mood_repository.dart';
import 'package:moodly/repositories/report_repository.dart';
import 'package:moodly/repositories/settings_repository.dart';
import 'package:moodly/services/auth_service.dart';
import 'package:moodly/services/report_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_harness.dart';

void main() {
  setupSqfliteFfiForTests();

  late AppDatabaseHolder holder;
  late MoodRepository moods;
  late ReportRepository reports;
  late SettingsRepository settings;
  late ReportService service;
  late List<http.Request> requests;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await SettingsRepository.load();
    holder = AppDatabaseHolder();
    final database = holder.database;
    moods = MoodRepository(database);
    reports = ReportRepository(database);
    requests = [];
    final tokens = InMemoryTokenStore();
    final api = ApiClient(
      baseUrl: 'http://localhost:8000',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/me') {
          return http.Response(
            '{"id": 7, "email": "u@moodly.test", "display_name": "U"}',
            200,
          );
        }
        // AI narrative endpoint: echo honest AI content.
        return http.Response(
          '{"source": "ai:test", "narrative": "AI summary generated from '
          'your aggregate statistics only.", "reflection_questions": '
          '["AI q1?", "AI q2?", "AI q3?"]}',
          200,
        );
      }),
      tokenStore: tokens,
    );
    final auth = AuthService(api: api, tokenStore: tokens, settings: settings);
    service = ReportService(
      moodRepository: moods,
      reportRepository: reports,
      api: api,
      auth: auth,
      settings: settings,
    );
  });

  tearDown(() => holder.dispose());

  /// Seeds a check-in for [day] with [mood] and [energy].
  Future<void> seed(DateTime day, Mood mood, {int energy = 3}) async {
    await moods.save(MoodEntry(date: day, mood: mood, energy: energy));
  }

  final now = DateTime(2026, 10, 30); // Friday of week Mon 26 → Sun 1 Nov

  group('ReportService period windows', () {
    test('current week starts on Monday and ends today', () {
      final week = ReportService.currentWeek(now: now);
      expect(week.start, DateTime(2026, 10, 26));
      expect(week.end, DateTime(2026, 10, 30));
    });

    test('current month starts on the 1st', () {
      final month = ReportService.currentMonth(now: now);
      expect(month.start, DateTime(2026, 10, 1));
      expect(month.end, DateTime(2026, 10, 30));
    });

    test('previous month has full boundaries', () {
      final prev = ReportService.previousMonth(now: now);
      expect(prev.start, DateTime(2026, 9, 1));
      expect(prev.end, DateTime(2026, 9, 30));
    });
  });

  group('Weekly report statistics (from real data)', () {
    test('computes counts, distribution and average energy', () async {
      // Week of Oct 26–30: 4 check-ins.
      await seed(DateTime(2026, 10, 26), Mood.good, energy: 4);
      await seed(DateTime(2026, 10, 27), Mood.great, energy: 5);
      await seed(DateTime(2026, 10, 28), Mood.good, energy: 4);
      await seed(DateTime(2026, 10, 29), Mood.low, energy: 2);
      // Outside the window (previous week) — must not be counted.
      await seed(DateTime(2026, 10, 20), Mood.terrible, energy: 1);

      final report = await service.generateWeeklyReport(now: now);
      final stats = report.data['stats'] as Map<String, Object?>;
      expect(stats['totalCheckins'], 4);
      expect(stats['checkInDays'], 4);
      expect(stats['spanDays'], 5); // Mon 26 .. Fri 30
      final dist = stats['moodDistribution'] as Map<String, Object?>;
      expect(dist['good'], 2);
      expect(dist['great'], 1);
      expect(dist['low'], 1);
      expect(stats['mostCommonMood'], 'good');
      expect(stats['averageEnergy'], 3.8); // (4+5+4+2)/4
      expect(report.periodStart, DateTime(2026, 10, 26));
      expect(report.kind, 'weekly');
    });

    test('empty period produces an honest empty report', () async {
      final report = await service.generateWeeklyReport(now: now);
      final stats = report.data['stats'] as Map<String, Object?>;
      expect(stats['totalCheckins'], 0);
      final narrative = report.data['narrative'] as String;
      expect(narrative, contains('No check-ins'));
      expect(report.narrativeSource, 'local_rules');
    });

    test('trend is up when the second half is clearly better', () async {
      await seed(DateTime(2026, 10, 26), Mood.terrible, energy: 1);
      await seed(DateTime(2026, 10, 27), Mood.low, energy: 2);
      await seed(DateTime(2026, 10, 29), Mood.great, energy: 5);
      await seed(DateTime(2026, 10, 30), Mood.great, energy: 5);
      final report = await service.generateWeeklyReport(now: now);
      final stats = report.data['stats'] as Map<String, Object?>;
      final trend = stats['trend'] as Map<String, Object?>;
      expect(trend['direction'], 'up');
    });

    test('trend is none when a half has no check-ins', () async {
      await seed(DateTime(2026, 10, 26), Mood.good, energy: 4);
      final report = await service.generateWeeklyReport(now: now);
      final stats = report.data['stats'] as Map<String, Object?>;
      final trend = stats['trend'] as Map<String, Object?>;
      expect(trend['direction'], 'none');
    });

    test('weekly reports never include a previous-period comparison', () async {
      await seed(DateTime(2026, 10, 26), Mood.good, energy: 4);
      final report = await service.generateWeeklyReport(now: now);
      expect(report.data['comparison'], isNull);
      // And no AI narrative call was made (not signed in / no consent).
      expect(
        requests.where((r) => r.url.path == '/ai/report-narrative'),
        isEmpty,
      );
    });
  });

  group('Monthly report comparisons (no invented numbers)', () {
    test('comparison appears only when both months have ≥3 entries', () async {
      // October: 4 entries.
      await seed(DateTime(2026, 10, 5), Mood.good, energy: 4);
      await seed(DateTime(2026, 10, 10), Mood.great, energy: 5);
      await seed(DateTime(2026, 10, 15), Mood.good, energy: 4);
      await seed(DateTime(2026, 10, 20), Mood.good, energy: 4);
      // September: only 2 entries → no comparison.
      await seed(DateTime(2026, 9, 5), Mood.low, energy: 2);
      await seed(DateTime(2026, 9, 15), Mood.low, energy: 2);

      var report = await service.generateMonthlyReport(now: now);
      expect(report.data['comparison'], isNull);

      // Add a third September entry → comparison unlocks.
      await seed(DateTime(2026, 9, 25), Mood.terrible, energy: 1);
      report = await service.generateMonthlyReport(now: now);
      final comparison = report.data['comparison'] as Map<String, Object?>;
      expect(comparison['previousPeriod'], isNotNull);
      // Oct avg mood score (4+5+4+4)/4 = 4.25 → 4.3; Sep (2+2+1)/3 = 1.667
      // → 1.7; delta ≈ +2.6. Same for energy in this fixture.
      expect(comparison['avgMoodDelta'], 2.6);
      expect(comparison['avgEnergyDelta'], 2.6); // 4.3 - 1.7
      expect(comparison['checkInDelta'], 1); // 4 - 3
    });

    test('missing previous month means no comparison at all', () async {
      await seed(DateTime(2026, 10, 5), Mood.good, energy: 4);
      await seed(DateTime(2026, 10, 10), Mood.great, energy: 5);
      await seed(DateTime(2026, 10, 15), Mood.good, energy: 4);
      final report = await service.generateMonthlyReport(now: now);
      expect(report.data['comparison'], isNull);
    });
  });

  group('AI narrative (opt-in, aggregates only)', () {
    test(
      'unauthenticated service instance never calls the AI endpoint',
      () async {
        await seed(DateTime(2026, 10, 26), Mood.good, energy: 4);
        await seed(DateTime(2026, 10, 27), Mood.great, energy: 5);
        // Even with consent flipped on, the service's OWN auth must be signed
        // in — a separate signed-in instance elsewhere changes nothing.
        await settings.setAiProcessingConsent(true);
        final report = await service.generateWeeklyReport(now: now);
        expect(report.narrativeSource, 'local_rules');
        expect(
          requests.where((r) => r.url.path == '/ai/report-narrative'),
          isEmpty,
        );
      },
    );

    test(
      'AI narrative request carries aggregates and no journal text',
      () async {
        // Directly exercise the endpoint contract via the service's API client
        // path is gated by its own auth; verify the aggregate builder instead
        // through a signed-in service.
        final tokens = InMemoryTokenStore()
          ..accessToken = 'a1'
          ..refreshToken = 'r1';
        final requests2 = <http.Request>[];
        final api = ApiClient(
          baseUrl: 'http://localhost:8000',
          client: MockClient((request) async {
            requests2.add(request);
            if (request.url.path == '/me') {
              return http.Response(
                '{"id": 7, "email": "u@moodly.test", "display_name": "U"}',
                200,
              );
            }
            return http.Response(
              '{"source": "ai:test", "narrative": "AI summary from your '
              'numbers.", "reflection_questions": ["a?", "b?", "c?"]}',
              200,
            );
          }),
          tokenStore: tokens,
        );
        final auth = AuthService(
          api: api,
          tokenStore: tokens,
          settings: settings,
        );
        await auth.restoreSession();
        await settings.setAiProcessingConsent(true);
        final signedService = ReportService(
          moodRepository: moods,
          reportRepository: reports,
          api: api,
          auth: auth,
          settings: settings,
        );

        await seed(DateTime(2026, 10, 26), Mood.good, energy: 4);
        await seed(DateTime(2026, 10, 27), Mood.great, energy: 5);
        final report = await signedService.generateWeeklyReport(now: now);

        expect(report.narrativeSource, 'ai:test');
        expect(report.isAiGenerated, isTrue);
        expect(report.data['narrative'], 'AI summary from your numbers.');
        final questions = report.data['reflectionQuestions'] as List;
        expect(questions, ['a?', 'b?', 'c?']);

        final aiCall = requests2.firstWhere(
          (r) => r.url.path == '/ai/report-narrative',
        );
        expect(aiCall.body, contains('total_checkins'));
        expect(aiCall.body, isNot(contains('journal')));
      },
    );

    test('AI failure silently keeps the local narrative', () async {
      final tokens = InMemoryTokenStore()
        ..accessToken = 'a1'
        ..refreshToken = 'r1';
      final api = ApiClient(
        baseUrl: 'http://localhost:8000',
        client: MockClient((request) async {
          if (request.url.path == '/me') {
            return http.Response(
              '{"id": 7, "email": "u@moodly.test", "display_name": "U"}',
              200,
            );
          }
          throw http.ClientException('offline');
        }),
        tokenStore: tokens,
      );
      final auth = AuthService(
        api: api,
        tokenStore: tokens,
        settings: settings,
      );
      await auth.restoreSession();
      await settings.setAiProcessingConsent(true);
      final offlineService = ReportService(
        moodRepository: moods,
        reportRepository: reports,
        api: api,
        auth: auth,
        settings: settings,
      );
      await seed(DateTime(2026, 10, 26), Mood.good, energy: 4);
      final report = await offlineService.generateWeeklyReport(now: now);
      expect(report.narrativeSource, 'local_rules');
      expect(report.data['narrative'], isNotEmpty);
    });
  });

  group('Report persistence', () {
    test('regenerating the same period replaces the stored report', () async {
      await seed(DateTime(2026, 10, 26), Mood.good, energy: 4);
      final first = await service.generateWeeklyReport(now: now);
      await seed(DateTime(2026, 10, 27), Mood.great, energy: 5);
      final second = await service.generateWeeklyReport(now: now);
      expect(second.id, first.id);
      final history = await service.history();
      expect(history, hasLength(1));
      final stats = second.data['stats'] as Map<String, Object?>;
      expect(stats['totalCheckins'], 2);
    });

    test('weekly and monthly reports for the same period coexist', () async {
      await seed(DateTime(2026, 10, 26), Mood.good, energy: 4);
      await service.generateWeeklyReport(now: now);
      await service.generateMonthlyReport(now: now);
      expect(await service.history(), hasLength(2));
    });

    test('deleteReport removes it from history', () async {
      await seed(DateTime(2026, 10, 26), Mood.good, energy: 4);
      final report = await service.generateWeeklyReport(now: now);
      await service.deleteReport(report.id!);
      expect(await service.history(), isEmpty);
    });
  });
}

/// Small holder so tearDown can close the database after each test.
class AppDatabaseHolder {
  AppDatabaseHolder() : database = inMemoryDatabase();
  final AppDatabase database;
  Future<void> dispose() => database.close();
}
