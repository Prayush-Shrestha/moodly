import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/network/api_client.dart';
import '../core/network/token_store.dart';
import '../repositories/settings_repository.dart';

/// Authenticated account snapshot held in memory after sign-in.
class UserSession {
  const UserSession({
    required this.userId,
    required this.email,
    required this.displayName,
  });

  final int userId;
  final String email;
  final String displayName;

  UserSession copyWith({String? email, String? displayName}) => UserSession(
    userId: userId,
    email: email ?? this.email,
    displayName: displayName ?? this.displayName,
  );
}

/// Result of a forgot-password request. In dev mode (backend
/// `MOODLY_DEV_MODE=1`) the reset token is returned so the flow is testable
/// without SMTP; in production the backend emails the link instead.
class ForgotPasswordResult {
  const ForgotPasswordResult({this.devResetToken});

  final String? devResetToken;
  bool get linkSent => devResetToken == null;
}

/// Optional account + session management (Phase 3).
///
/// Everything works without an account (local-only mode); signing in only
/// enables AI reflection and cloud sync. Tokens live in [TokenStore]
/// (platform-secure); no passwords are ever stored.
class AuthService extends ChangeNotifier {
  AuthService({
    required this._api,
    required TokenStore tokenStore,
    required this._settings,
  }) : _tokens = tokenStore {
    _api.attachTokenStore(tokenStore);
    _api.onRefresh = _refresh;
  }

  final ApiClient _api;
  final TokenStore _tokens;
  final SettingsRepository _settings;

  UserSession? _session;
  bool _restoring = false;
  String? _lastError;

  UserSession? get session => _session;
  bool get isSignedIn => _session != null;
  bool get isRestoring => _restoring;
  String? get lastError => _lastError;

  // --- session lifecycle ------------------------------------------------------

  /// Restores a previous session from secure storage. Never throws: an
  /// offline start keeps the session (tokens are validated lazily), and any
  /// platform-channel problem (e.g. tests) degrades to local-only mode.
  Future<void> restoreSession() async {
    if (_restoring || _session != null) return;
    _restoring = true;
    notifyListeners();
    try {
      final access = await _tokens.readAccessToken();
      final refresh = await _tokens.readRefreshToken();
      if (access == null || refresh == null) return;
      try {
        final me = await _api.get('/me');
        _session = _sessionFromMe(me);
        notifyListeners();
      } on ApiException catch (e) {
        if (e.statusCode == 401) {
          // Access token expired: try one refresh.
          final ok = await _refresh();
          if (ok != null) {
            final me = await _api.get('/me');
            _session = _sessionFromMe(me);
            notifyListeners();
          } else {
            await _tokens.clear();
          }
        }
        // Offline (statusCode == null): keep the session optimistically.
        else if (e.isOffline) {
          _session = const UserSession(userId: -1, email: '', displayName: '');
          notifyListeners();
        }
      }
    } catch (_) {
      // Secure storage unavailable (tests/unsupported platform): local-only.
    } finally {
      _restoring = false;
      notifyListeners();
    }
  }

  UserSession _sessionFromMe(Map<String, Object?> me) => UserSession(
    userId: me['id'] as int? ?? -1,
    email: me['email'] as String? ?? '',
    displayName: me['display_name'] as String? ?? '',
  );

  /// Called by ApiClient after a 401: rotates the refresh token once.
  Future<String?> _refresh() async {
    final refresh = await _tokens.readRefreshToken();
    if (refresh == null) return null;
    try {
      final pair = await _api.post(
        '/auth/refresh',
        body: {'refresh_token': refresh},
        auth: false,
      );
      final access = pair['access_token'] as String?;
      final newRefresh = pair['refresh_token'] as String?;
      if (access == null || newRefresh == null) return null;
      await _tokens.saveTokens(accessToken: access, refreshToken: newRefresh);
      return access;
    } on ApiException {
      // Refresh failed (revoked/expired): end the session locally.
      _session = null;
      await _tokens.clear();
      notifyListeners();
      return null;
    }
  }

  // --- auth flows ---------------------------------------------------------------

  Future<UserSession> register({
    required String email,
    required String password,
    String displayName = '',
  }) async {
    final payload = await _api.post(
      '/auth/register',
      body: {
        'email': email,
        'password': password,
        if (displayName.isNotEmpty) 'display_name': displayName,
      },
      auth: false,
    );
    return _adopt(payload);
  }

  Future<UserSession> login({
    required String email,
    required String password,
  }) async {
    final payload = await _api.post(
      '/auth/login',
      body: {'email': email, 'password': password},
      auth: false,
    );
    return _adopt(payload);
  }

  UserSession _adopt(Map<String, Object?> payload) {
    final access = payload['access_token'] as String?;
    final refresh = payload['refresh_token'] as String?;
    final user = payload['user'];
    if (access == null || refresh == null || user is! Map) {
      throw const ApiException(message: 'Unexpected response from the server.');
    }
    _session = _sessionFromMe(Map<String, Object?>.from(user));
    _lastError = null;
    // Fire-and-forget: mirror local consent state to the account record.
    unawaited(_mirrorConsents());
    notifyListeners();
    // Tokens are persisted after state update; failures here just mean the
    // user must sign in again next launch.
    _tokens.saveTokens(accessToken: access, refreshToken: refresh);
    return _session!;
  }

  Future<void> logout() async {
    final refresh = await _tokens.readRefreshToken();
    if (refresh != null) {
      try {
        await _api.post('/auth/logout', body: {'refresh_token': refresh});
      } catch (_) {
        // Best effort — local logout always proceeds.
      }
    }
    _session = null;
    await _tokens.clear();
    await _settings.clearSyncState();
    notifyListeners();
  }

  Future<ForgotPasswordResult> forgotPassword(String email) async {
    final payload = await _api.post(
      '/auth/forgot-password',
      body: {'email': email},
      auth: false,
    );
    final token = payload['reset_token'];
    return ForgotPasswordResult(devResetToken: token is String ? token : null);
  }

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    await _api.post(
      '/auth/reset-password',
      body: {'token': token, 'password': newPassword},
      auth: false,
    );
  }

  // --- profile & consents -------------------------------------------------------

  Future<void> refreshProfile() async {
    if (!isSignedIn) return;
    try {
      final me = await _api.get('/me');
      _session = _sessionFromMe(me);
      notifyListeners();
    } on ApiException catch (e) {
      if (e.statusCode == 401) _session = null;
      rethrow;
    }
  }

  Future<void> updateDisplayName(String name) async {
    final me = await _api.patch('/me', body: {'display_name': name});
    _session = _sessionFromMe(me);
    notifyListeners();
  }

  /// Mirrors local privacy consents to the account record (the server checks
  /// journal_upload_consent before accepting journal rows on sync).
  Future<void> _mirrorConsents() async {
    if (!isSignedIn || (_session?.userId ?? -1) < 0) return;
    try {
      await _api.patch(
        '/me',
        body: {
          'journal_upload_consent': _settings.journalUploadConsent,
          'cloud_sync_consent': _settings.cloudSyncEnabled,
        },
      );
    } catch (_) {
      // Non-critical; retried on next sign-in/consent change.
    }
  }

  /// Called by consent screens after the user flips a switch.
  Future<void> onConsentChanged() => _mirrorConsents();

  Future<void> deleteAccount() async {
    await _api.delete('/me');
    _session = null;
    await _tokens.clear();
    await _settings.clearSyncState();
    await _settings.setCloudSyncEnabled(false);
    await _settings.setJournalUploadConsent(false);
    notifyListeners();
  }
}
