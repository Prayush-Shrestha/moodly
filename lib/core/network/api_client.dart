import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'token_store.dart';

/// Typed API failure. [statusCode] is null when the request never reached the
/// server (offline/DNS/timeout).
class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.statusCode,
    this.code,
    this.fieldErrors = const {},
  });

  final String message;
  final int? statusCode;
  final String? code;

  /// Field-level validation messages from the backend, keyed by field name.
  final Map<String, String> fieldErrors;

  bool get isOffline => statusCode == null;
  bool get isUnauthorized => statusCode == 401;
  bool get isRateLimited => statusCode == 429;

  @override
  String toString() => message;
}

/// Minimal REST client for the Moodly backend.
///
/// - Bearer token injected from [TokenStore]; a 401 triggers ONE transparent
///   refresh (delegated to [onRefresh]) and a single retry.
/// - All requests have a hard timeout so the UI never hangs offline.
/// - Responses are validated; error payloads never echo journal content.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
    this._tokenStore,
  }) : _client = client ?? http.Client();

  String baseUrl;
  final http.Client _client;
  final Duration timeout;
  TokenStore? _tokenStore;

  /// Registered by [AuthService]; returns a fresh access token or null.
  Future<String?> Function()? onRefresh;

  void attachTokenStore(TokenStore store) => _tokenStore = store;

  // --- verbs ------------------------------------------------------------------

  Future<Map<String, Object?>> get(String path, {bool auth = true}) =>
      _send('GET', path, auth: auth);

  Future<Map<String, Object?>> post(
    String path, {
    Map<String, Object?>? body,
    bool auth = true,
  }) => _send('POST', path, body: body, auth: auth);

  Future<Map<String, Object?>> patch(
    String path, {
    Map<String, Object?>? body,
    bool auth = true,
  }) => _send('PATCH', path, body: body, auth: auth);

  Future<void> delete(String path, {bool auth = true}) async {
    await _send('DELETE', path, auth: auth);
  }

  // --- internals ---------------------------------------------------------------

  Future<Map<String, Object?>> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    bool auth = true,
    bool isRetry = false,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (auth && _tokenStore != null) {
      final token = await _tokenStore!.readAccessToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }

    final http.StreamedResponse streamed;
    try {
      final request = http.Request(method, uri)
        ..headers.addAll(headers)
        ..body = body == null ? '' : jsonEncode(body);
      streamed = await _client.send(request).timeout(timeout);
    } on TimeoutException {
      throw const ApiException(
        message: 'The request timed out. Check your connection and try again.',
      );
    } on http.ClientException {
      throw const ApiException(
        message:
            'Could not reach the server. You can keep using Moodly '
            'offline — your data stays on this device.',
      );
    } on FormatException {
      throw const ApiException(message: 'Unexpected server response.');
    }
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 401 && auth && !isRetry) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        return _send(method, path, body: body, auth: auth, isRetry: true);
      }
    }

    return _decode(response);
  }

  Future<bool> _tryRefresh() async {
    final refresh = onRefresh;
    if (refresh == null) return false;
    try {
      return await refresh() != null;
    } catch (_) {
      return false;
    }
  }

  Map<String, Object?> _decode(http.Response response) {
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    Map<String, Object?> json;
    try {
      final decoded = text.isEmpty ? <String, Object?>{} : jsonDecode(text);
      json = decoded is Map<String, Object?> ? decoded : <String, Object?>{};
    } on FormatException {
      json = <String, Object?>{};
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return json;
    }

    throw _apiException(response.statusCode, json);
  }

  static ApiException _apiException(int status, Map<String, Object?> json) {
    final detail = json['detail'];
    String message;
    if (status >= 500) {
      // Server errors are never echoed — the detail may contain internals.
      message = 'The server had a problem. Please try again shortly.';
    } else if (detail is String && detail.isNotEmpty) {
      message = detail;
    } else if (status == 429) {
      message = 'Too many requests — please wait a moment and try again.';
    } else {
      message = 'Request failed (HTTP $status).';
    }

    final fieldErrors = <String, String>{};
    final errors = json['errors'];
    if (errors is List) {
      for (final raw in errors) {
        if (raw is Map && raw['field'] is String) {
          fieldErrors[raw['field'] as String] =
              raw['message']?.toString() ?? '';
        }
      }
    }
    final code = json['code'];
    return ApiException(
      message: message,
      statusCode: status,
      code: code is String ? code : null,
      fieldErrors: fieldErrors,
    );
  }

  void dispose() => _client.close();
}
