import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moodly/core/network/api_client.dart';
import 'package:moodly/core/network/token_store.dart';
import 'package:moodly/repositories/settings_repository.dart';
import 'package:moodly/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late InMemoryTokenStore tokens;
  late SettingsRepository settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await SettingsRepository.load();
    tokens = InMemoryTokenStore();
  });

  AuthService build(MockClient mock) {
    final api = ApiClient(
      baseUrl: 'http://localhost:8000',
      client: mock,
      tokenStore: tokens,
    );
    return AuthService(api: api, tokenStore: tokens, settings: settings);
  }

  const loginResponse =
      '{"access_token": "a1", "refresh_token": "r1", '
      '"expires_in": 1800, "user": {"id": 7, "email": "u@moodly.test", '
      '"display_name": "U", "journal_upload_consent": false, '
      '"cloud_sync_consent": false, "ai_processing_consent": false}}';

  group('AuthService registration/login', () {
    test('register stores tokens and session', () async {
      final auth = build(
        MockClient((request) async {
          expect(request.url.path, '/auth/register');
          return http.Response(loginResponse, 201);
        }),
      );
      final session = await auth.register(
        email: 'u@moodly.test',
        password: 'passw0rd1',
      );
      expect(auth.isSignedIn, isTrue);
      expect(session.email, 'u@moodly.test');
      expect(await tokens.readAccessToken(), 'a1');
      expect(await tokens.readRefreshToken(), 'r1');
    });

    test('login failure keeps user signed out and stores nothing', () async {
      final auth = build(
        MockClient(
          (request) async =>
              http.Response('{"detail": "Incorrect email or password"}', 401),
        ),
      );
      await expectLater(
        auth.login(email: 'u@moodly.test', password: 'wrong9999'),
        throwsA(isA<ApiException>()),
      );
      expect(auth.isSignedIn, isFalse);
      expect(await tokens.readAccessToken(), isNull);
    });

    test('consents are mirrored to the account after sign-in', () async {
      await settings.setJournalUploadConsent(true);
      var patchedBody = '';
      final auth = build(
        MockClient((request) async {
          if (request.url.path == '/auth/login') {
            return http.Response(loginResponse, 200);
          }
          if (request.method == 'PATCH' && request.url.path == '/me') {
            patchedBody = request.body;
            return http.Response(
              '{"id": 7, "email": "u@moodly.test", "display_name": "U", '
              '"journal_upload_consent": true, "cloud_sync_consent": false, '
              '"ai_processing_consent": false}',
              200,
            );
          }
          return http.Response('{}', 200);
        }),
      );
      await auth.login(email: 'u@moodly.test', password: 'passw0rd1');
      await auth.onConsentChanged();
      expect(patchedBody, contains('"journal_upload_consent":true'));
    });
  });

  group('AuthService session restore', () {
    test('valid tokens restore the session via /me', () async {
      await tokens.saveTokens(accessToken: 'a1', refreshToken: 'r1');
      final auth = build(
        MockClient((request) async {
          expect(request.url.path, '/me');
          return http.Response(
            '{"id": 7, "email": "u@moodly.test", "display_name": "U"}',
            200,
          );
        }),
      );
      await auth.restoreSession();
      expect(auth.isSignedIn, isTrue);
      expect(auth.session!.email, 'u@moodly.test');
    });

    test('offline restore keeps the session optimistically', () async {
      await tokens.saveTokens(accessToken: 'a1', refreshToken: 'r1');
      final auth = build(
        MockClient((request) async => throw http.ClientException('no network')),
      );
      await auth.restoreSession();
      expect(auth.isSignedIn, isTrue);
    });

    test('no stored tokens means no session', () async {
      final auth = build(
        MockClient((request) async => http.Response('{}', 200)),
      );
      await auth.restoreSession();
      expect(auth.isSignedIn, isFalse);
    });
  });

  group('AuthService token refresh via ApiClient', () {
    test('a 401 triggers one refresh and retries with new token', () async {
      await tokens.saveTokens(accessToken: 'expired', refreshToken: 'r1');
      var meCalls = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost:8000',
        client: MockClient((request) async {
          if (request.url.path == '/me') {
            meCalls++;
            if (meCalls == 1) {
              return http.Response('{"detail": "expired"}', 401);
            }
            return http.Response(
              '{"id": 7, "email": "u@moodly.test", "display_name": "U"}',
              200,
            );
          }
          if (request.url.path == '/auth/refresh') {
            return http.Response(
              '{"access_token": "a2", "refresh_token": "r2", '
              '"expires_in": 1800}',
              200,
            );
          }
          return http.Response('{}', 404);
        }),
        tokenStore: tokens,
      );
      final auth = AuthService(
        api: api,
        tokenStore: tokens,
        settings: settings,
      );

      await auth.restoreSession();
      expect(auth.isSignedIn, isTrue);
      // The old access token was rotated.
      expect(await tokens.readAccessToken(), 'a2');
      expect(await tokens.readRefreshToken(), 'r2');
    });

    test('revoked refresh token clears the session', () async {
      await tokens.saveTokens(accessToken: 'expired', refreshToken: 'dead');
      final api = ApiClient(
        baseUrl: 'http://localhost:8000',
        client: MockClient((request) async {
          if (request.url.path == '/auth/refresh') {
            return http.Response('{"detail": "revoked"}', 401);
          }
          return http.Response('{"detail": "expired"}', 401);
        }),
        tokenStore: tokens,
      );
      final auth = AuthService(
        api: api,
        tokenStore: tokens,
        settings: settings,
      );

      await auth.restoreSession();
      expect(auth.isSignedIn, isFalse);
      expect(await tokens.readAccessToken(), isNull);
      expect(await tokens.readRefreshToken(), isNull);
    });
  });

  group('AuthService logout and deletion', () {
    test('logout revokes server-side and clears local state', () async {
      var revoked = false;
      final auth = build(
        MockClient((request) async {
          if (request.url.path == '/auth/login') {
            return http.Response(loginResponse, 200);
          }
          if (request.url.path == '/auth/logout') {
            revoked = true;
            return http.Response('', 204);
          }
          return http.Response('{}', 200);
        }),
      );
      await auth.login(email: 'u@moodly.test', password: 'passw0rd1');
      await auth.logout();
      expect(revoked, isTrue);
      expect(auth.isSignedIn, isFalse);
      expect(await tokens.readAccessToken(), isNull);
    });

    test('logout proceeds locally even when the server call fails', () async {
      final auth = build(
        MockClient((request) async {
          if (request.url.path == '/auth/login') {
            return http.Response(loginResponse, 200);
          }
          return http.Response('{"detail": "err"}', 500);
        }),
      );
      await auth.login(email: 'u@moodly.test', password: 'passw0rd1');
      await auth.logout(); // must not throw
      expect(auth.isSignedIn, isFalse);
    });

    test('deleteAccount clears session, tokens and sync consents', () async {
      await settings.setCloudSyncEnabled(true);
      await settings.setJournalUploadConsent(true);
      final auth = build(
        MockClient((request) async {
          if (request.url.path == '/auth/login') {
            return http.Response(loginResponse, 200);
          }
          return http.Response('', 204);
        }),
      );
      await auth.login(email: 'u@moodly.test', password: 'passw0rd1');
      await auth.deleteAccount();
      expect(auth.isSignedIn, isFalse);
      expect(await tokens.readAccessToken(), isNull);
      expect(settings.cloudSyncEnabled, isFalse);
      expect(settings.journalUploadConsent, isFalse);
    });
  });

  group('AuthService password reset', () {
    test('dev mode returns the reset token', () async {
      final auth = build(
        MockClient(
          (request) async =>
              http.Response('{"is_dev": true, "reset_token": "tok123"}', 200),
        ),
      );
      final result = await auth.forgotPassword('u@moodly.test');
      expect(result.devResetToken, 'tok123');
      expect(result.linkSent, isFalse);
    });

    test('production mode reports the link as sent', () async {
      final auth = build(
        MockClient((request) async => http.Response('{"is_dev": false}', 200)),
      );
      final result = await auth.forgotPassword('u@moodly.test');
      expect(result.devResetToken, isNull);
      expect(result.linkSent, isTrue);
    });

    test('resetPassword posts the token and new password', () async {
      Object? body;
      final auth = build(
        MockClient((request) async {
          body = request.body;
          return http.Response('', 204);
        }),
      );
      await auth.resetPassword(token: 'tok123', newPassword: 'brandNew99');
      expect(body, contains('"token":"tok123"'));
      expect(body, contains('"password":"brandNew99"'));
    });
  });
}
