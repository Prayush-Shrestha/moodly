import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moodly/core/network/api_client.dart';
import 'package:moodly/core/network/token_store.dart';

void main() {
  late InMemoryTokenStore tokens;

  setUp(() {
    tokens = InMemoryTokenStore();
  });

  ApiClient client(MockClient mock) => ApiClient(
    baseUrl: 'http://localhost:8000',
    client: mock,
    tokenStore: tokens,
  );

  group('ApiClient success paths', () {
    test('GET returns decoded JSON map', () async {
      final api = client(
        MockClient((request) async {
          expect(request.url.path, '/health');
          expect(request.method, 'GET');
          return http.Response('{"status": "ok"}', 200);
        }),
      );
      final result = await api.get('/health', auth: false);
      expect(result['status'], 'ok');
    });

    test('POST serializes the body as JSON', () async {
      Object? seen;
      final api = client(
        MockClient((request) async {
          seen = request.body;
          return http.Response('{}', 200);
        }),
      );
      await api.post('/auth/login', body: {'email': 'a@b.co'}, auth: false);
      expect(seen, contains('"email":"a@b.co"'));
    });

    test('bearer token is attached from the token store', () async {
      await tokens.saveTokens(accessToken: 'access-123', refreshToken: 'r');
      final api = client(
        MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer access-123');
          return http.Response('{}', 200);
        }),
      );
      await api.get('/me');
    });

    test('auth: false omits the Authorization header', () async {
      await tokens.saveTokens(accessToken: 'access-123', refreshToken: 'r');
      final api = client(
        MockClient((request) async {
          expect(request.headers.containsKey('Authorization'), isFalse);
          return http.Response('{}', 200);
        }),
      );
      await api.get('/health', auth: false);
    });
  });

  group('ApiClient error mapping', () {
    test('401 raises ApiException with isUnauthorized', () async {
      final api = client(
        MockClient((request) async => http.Response('{"detail": "nope"}', 401)),
      );
      final error = await _capture(() => api.get('/me'));
      expect(error, isA<ApiException>());
      expect(error!.statusCode, 401);
      expect(error.isUnauthorized, isTrue);
      expect(error.message, 'nope');
    });

    test('429 raises rate-limited ApiException', () async {
      final api = client(
        MockClient((request) async => http.Response('{}', 429)),
      );
      final error = await _capture(() => api.get('/ai/status'));
      expect(error!.isRateLimited, isTrue);
    });

    test('500 maps to a friendly message without echoing detail', () async {
      final api = client(
        MockClient(
          (request) async => http.Response('{"detail": "Traceback..."}', 500),
        ),
      );
      final error = await _capture(() => api.get('/me'));
      expect(error!.statusCode, 500);
      expect(error.message, isNot(contains('Traceback')));
    });

    test('field errors are parsed from the validation envelope', () async {
      final api = client(
        MockClient(
          (request) async => http.Response(
            '{"code": "validation_error", "errors": '
            '[{"field": "email", "message": "Invalid email"}]}',
            422,
          ),
        ),
      );
      final error = await _capture(() => api.post('/auth/register', body: {}));
      expect(error!.fieldErrors['email'], 'Invalid email');
      expect(error.code, 'validation_error');
    });

    test('connection failure is offline (statusCode null)', () async {
      final api = client(
        MockClient(
          (request) async => throw http.ClientException('connection refused'),
        ),
      );
      final error = await _capture(() => api.get('/health', auth: false));
      expect(error!.isOffline, isTrue);
      expect(error.message, contains('offline'));
    });

    test(
      'error message never contains the journal-like request body',
      () async {
        final api = client(
          MockClient(
            (request) async => http.Response('{"detail": "bad"}', 400),
          ),
        );
        final error = await _capture(
          () => api.post(
            '/ai/reflection',
            body: {'journal_body': 'secret words'},
          ),
        );
        expect(error!.message, isNot(contains('secret words')));
      },
    );
  });

  group('ApiClient 401 refresh + retry', () {
    test('one transparent refresh then retry succeeds', () async {
      await tokens.saveTokens(accessToken: 'expired', refreshToken: 'r1');
      var calls = 0;
      final api = client(
        MockClient((request) async {
          calls++;
          if (request.url.path == '/me') {
            // First call fails; the retry carries the refreshed token.
            if (calls == 1) {
              return http.Response('{"detail": "expired"}', 401);
            }
            expect(request.headers['Authorization'], 'Bearer fresh');
            return http.Response('{"id": 1}', 200);
          }
          return http.Response('{}', 404);
        }),
      );
      // Mirrors AuthService: rotate and persist the new token pair.
      api.onRefresh = () async {
        await tokens.saveTokens(accessToken: 'fresh', refreshToken: 'r2');
        return 'fresh';
      };

      final result = await api.get('/me');
      expect(result['id'], 1);
      expect(await tokens.readAccessToken(), 'fresh');
    });

    test('retried request that still 401s raises (no infinite loop)', () async {
      var meCalls = 0;
      final api = client(
        MockClient((request) async {
          if (request.url.path == '/auth/refresh') {
            return http.Response('{}', 200);
          }
          meCalls++;
          return http.Response('{"detail": "expired"}', 401);
        }),
      );
      api.onRefresh = () async => 'fresh';

      final error = await _capture(() => api.get('/me'));
      expect(error!.statusCode, 401);
      expect(meCalls, 2); // original + exactly one retry
    });

    test('failed refresh surfaces the original 401', () async {
      final api = client(
        MockClient(
          (request) async => http.Response('{"detail": "expired"}', 401),
        ),
      );
      api.onRefresh = () async => null; // refresh failed

      final error = await _capture(() => api.get('/me'));
      expect(error!.statusCode, 401);
    });
  });
}

Future<ApiException?> _capture(Future<Object?> Function() run) async {
  try {
    await run();
    return null;
  } on ApiException catch (e) {
    return e;
  }
}
