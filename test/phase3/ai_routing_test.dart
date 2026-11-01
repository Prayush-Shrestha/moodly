import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moodly/core/network/api_client.dart';
import 'package:moodly/core/network/token_store.dart';
import 'package:moodly/models/journal_entry.dart';
import 'package:moodly/repositories/settings_repository.dart';
import 'package:moodly/services/ai_service.dart';
import 'package:moodly/services/auth_service.dart';
import 'package:moodly/services/journal_reflection_service.dart';
import 'package:moodly/services/remote_ai_service.dart';
import 'package:moodly/services/routing_ai_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Scriptable local service that records invocations.
class FakeLocalAiService implements AiService {
  int calls = 0;

  @override
  bool get isRuleBased => true;

  @override
  Future<JournalReflectionResult> generateReflection(JournalEntry entry) async {
    calls++;
    return const JournalReflectionResult(
      summary: 'Local summary of your entry.',
      detectedEmotions: ['calm'],
      themes: ['reflective'],
      reflectionQuestions: ['Q1?', 'Q2?', 'Q3?'],
      isRuleBased: true,
    );
  }
}

/// Builds a RemoteAiService on top of [mock]. When [signIn] is true the
/// session is established first via a `/me` round trip, so availability
/// additionally depends on the consent flag under test.
Future<
  ({RemoteAiService remote, AuthService auth, SettingsRepository settings})
>
remoteStack(MockClient mock, {required bool signIn}) async {
  final settings = _settings;
  final tokens = InMemoryTokenStore();
  final api = ApiClient(
    baseUrl: 'http://localhost:8000',
    client: mock,
    tokenStore: tokens,
  );
  final auth = AuthService(api: api, tokenStore: tokens, settings: settings);
  if (signIn) {
    // Persist fake tokens, then let restoreSession hit /me (the mock must
    // answer it — the default route below returns a valid profile).
    await tokens.saveTokens(accessToken: 'a1', refreshToken: 'r1');
    await auth.restoreSession();
  }
  return (
    remote: RemoteAiService(api: api, auth: auth, settings: settings),
    auth: auth,
    settings: settings,
  );
}

late SettingsRepository _settings;

void main() {
  final entry = JournalEntry(
    date: DateTime(2026, 10, 30),
    body: 'I finished my project and felt proud.',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _settings = await SettingsRepository.load();
  });

  /// Wraps an arbitrary handler so /me always answers (needed by restore).
  MockClient mockWithRoutes(
    Future<http.Response> Function(http.Request) handler,
  ) => MockClient((request) async {
    if (request.url.path == '/me') {
      return http.Response(
        '{"id": 7, "email": "u@moodly.test", "display_name": "U"}',
        200,
      );
    }
    return handler(request);
  });

  group('RemoteAiService availability gates', () {
    test('not available without sign-in (even with consent)', () async {
      await _settings.setAiProcessingConsent(true);
      final stack = await remoteStack(
        mockWithRoutes((request) async => http.Response('{}', 200)),
        signIn: false,
      );
      expect(stack.remote.isAvailable, isFalse);
    });

    test('not available without consent (even when signed in)', () async {
      await _settings.setAiProcessingConsent(false);
      final stack = await remoteStack(
        mockWithRoutes((request) async => http.Response('{}', 200)),
        signIn: true,
      );
      expect(stack.auth.isSignedIn, isTrue);
      expect(stack.remote.isAvailable, isFalse);
    });

    test('reflection throws before consent instead of sending data', () async {
      var sent = false;
      final stack = await remoteStack(
        mockWithRoutes((request) async {
          sent = true;
          return http.Response('{}', 200);
        }),
        signIn: true,
      );
      await expectLater(
        stack.remote.generateReflection(entry),
        throwsA(isA<ApiException>()),
      );
      expect(sent, isFalse);
    });

    test('available when signed in with consent', () async {
      await _settings.setAiProcessingConsent(true);
      final stack = await remoteStack(
        mockWithRoutes((request) async => http.Response('{}', 200)),
        signIn: true,
      );
      expect(stack.remote.isAvailable, isTrue);
    });
  });

  group('RemoteAiService parsing', () {
    test('maps the payload including explicit/inferred emotions', () async {
      await _settings.setAiProcessingConsent(true);
      String? sentBody;
      final stack = await remoteStack(
        mockWithRoutes((request) async {
          sentBody = request.body;
          return http.Response(
            '{"source": "ai:test", "summary": "You finished something big.", '
            '"explicit_emotions": ["proud"], "inferred_emotions": ["relieved"], '
            '"themes": ["productive"], "positive_observations": ["Finished it"], '
            '"challenges": ["Busy week"], "reflection_questions": '
            '["What helped?", "How did it feel?", "Next time?"]}',
            200,
          );
        }),
        signIn: true,
      );
      final result = await stack.remote.generateReflection(entry);
      expect(result.provider, 'ai:test');
      expect(result.isRuleBased, isFalse);
      expect(result.explicitEmotions, ['proud']);
      expect(result.inferredEmotions, ['relieved']);
      expect(result.positiveObservations, ['Finished it']);
      expect(result.challenges, ['Busy week']);
      expect(result.reflectionQuestions, hasLength(3));
      // One entry's text is sent per reflection — the consented contract.
      expect(sentBody, contains('finished my project'));
      expect(sentBody, contains('"consent_given":true'));
    });

    test('backend local_rules fallback stays rule-based', () async {
      await _settings.setAiProcessingConsent(true);
      final stack = await remoteStack(
        mockWithRoutes(
          (request) async => http.Response(
            '{"source": "local_rules", "summary": "Local summary.", '
            '"explicit_emotions": [], "inferred_emotions": [], '
            '"themes": [], "positive_observations": [], "challenges": [], '
            '"reflection_questions": ["a?", "b?", "c?"]}',
            200,
          ),
        ),
        signIn: true,
      );
      final result = await stack.remote.generateReflection(entry);
      expect(result.isRuleBased, isTrue);
      expect(result.provider, 'local_rules');
    });

    test('fetchStatus reflects the backend mode', () async {
      final stack = await remoteStack(
        mockWithRoutes(
          (request) async => http.Response(
            '{"ai_enabled": false, "provider": "none", '
            '"mode": "local_rules"}',
            200,
          ),
        ),
        signIn: true,
      );
      final status = await stack.remote.fetchStatus();
      expect(status.aiEnabled, isFalse);
      expect(status.mode, 'local_rules');
    });
  });

  group('RoutingAiService fallback', () {
    Future<RoutingAiService> route({
      required FakeLocalAiService local,
      MockClient? mock,
      bool signedIn = true,
      bool consent = true,
    }) async {
      await _settings.setAiProcessingConsent(consent);
      final stack = await remoteStack(
        mock ?? mockWithRoutes((request) async => http.Response('{}', 200)),
        signIn: signedIn,
      );
      return RoutingAiService(local: local, remote: stack.remote);
    }

    test('uses local immediately when remote is unavailable', () async {
      final local = FakeLocalAiService();
      final routing = await route(local: local, signedIn: false);
      final result = await routing.generateReflection(entry);
      expect(result.isRuleBased, isTrue);
      expect(local.calls, 1);
      expect(routing.lastRemoteFailure, isNull);
      expect(routing.canUseRemote, isFalse);
      expect(routing.isRuleBased, isTrue);
    });

    test('offline remote failure falls back to local with reason', () async {
      final local = FakeLocalAiService();
      final routing = await route(
        local: local,
        mock: mockWithRoutes(
          (request) async => throw http.ClientException('no network'),
        ),
      );
      final result = await routing.generateReflection(entry);
      expect(result.isRuleBased, isTrue);
      expect(local.calls, 1);
      expect(routing.lastRemoteFailure, 'offline');
    });

    test('server error falls back to local with reason', () async {
      final local = FakeLocalAiService();
      final routing = await route(
        local: local,
        mock: mockWithRoutes(
          (request) async => http.Response('{"detail": "boom"}', 500),
        ),
      );
      await routing.generateReflection(entry);
      expect(routing.lastRemoteFailure, 'server_error');
    });

    test('429 falls back with a rate-limited reason', () async {
      final local = FakeLocalAiService();
      final routing = await route(
        local: local,
        mock: mockWithRoutes(
          (request) async => http.Response('{"detail": "slow down"}', 429),
        ),
      );
      await routing.generateReflection(entry);
      expect(routing.lastRemoteFailure, 'rate_limited');
    });

    test('successful remote result skips the local service entirely', () async {
      final local = FakeLocalAiService();
      final routing = await route(
        local: local,
        mock: mockWithRoutes(
          (request) async => http.Response(
            '{"source": "ai:test", "summary": "AI summary here.", '
            '"explicit_emotions": ["happy"], "inferred_emotions": [], '
            '"themes": [], "positive_observations": [], "challenges": [], '
            '"reflection_questions": ["a?", "b?", "c?"]}',
            200,
          ),
        ),
      );
      final result = await routing.generateReflection(entry);
      expect(result.isRuleBased, isFalse);
      expect(result.provider, 'ai:test');
      expect(local.calls, 0);
      expect(routing.lastRemoteFailure, isNull);
      expect(routing.isRuleBased, isFalse);
    });
  });

  group('LocalAiService (Phase 2 fallback)', () {
    test(
      'produces a rule-based reflection with the extended result shape',
      () async {
        final service = LocalAiService(JournalReflectionService());
        final result = await service.generateReflection(entry);
        expect(service.isRuleBased, isTrue);
        expect(result.isRuleBased, isTrue);
        expect(result.provider, 'local_rules');
        // The local service derives questions from detected patterns, so the
        // count varies — but it always offers at least one.
        expect(result.reflectionQuestions, isNotEmpty);
        // Local reflections never claim inferred emotions.
        expect(result.inferredEmotions, isEmpty);
      },
    );
  });
}
