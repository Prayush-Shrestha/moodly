import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted app preferences: theme plus Phase 3 privacy/sync settings.
///
/// Privacy defaults are deliberately conservative: every consent flag starts
/// `false`; nothing leaves the device until the user opts in on the consent
/// screens.
class SettingsRepository extends ChangeNotifier {
  SettingsRepository._(this._prefs)
    : themeMode = _read(_prefs),
      aiProcessingConsent = _readBool(_prefs, _kAiConsent),
      cloudSyncEnabled = _readBool(_prefs, _kCloudSyncEnabled),
      journalUploadConsent = _readBool(_prefs, _kJournalUploadConsent),
      serverBaseUrl = _prefs.getString(_kServerUrl) ?? defaultServerUrl,
      syncCursor = _prefs.getString(_kSyncCursor),
      lastSyncAtMs = _prefs.getInt(_kLastSyncAt);

  static Future<SettingsRepository> load() async =>
      SettingsRepository._(await SharedPreferences.getInstance());

  static const String _kThemeMode = 'theme_mode';
  static const String _kAiConsent = 'ai_processing_consent';
  static const String _kCloudSyncEnabled = 'cloud_sync_enabled';
  static const String _kJournalUploadConsent = 'journal_upload_consent';
  static const String _kServerUrl = 'server_base_url';
  static const String _kSyncCursor = 'sync_cursor';
  static const String _kLastSyncAt = 'last_sync_at_ms';

  /// Android emulator loopback alias: `10.0.2.2` reaches the host machine.
  /// Real devices can change this in Settings → Account & sync.
  static const String defaultServerUrl = 'http://10.0.2.2:8000';

  final SharedPreferences _prefs;

  ThemeMode themeMode;

  /// Explicit consent before any journal text is processed by the AI backend.
  bool aiProcessingConsent;

  /// Master switch for optional cloud synchronization.
  bool cloudSyncEnabled;

  /// Explicit consent before journal entries may be uploaded (sync).
  bool journalUploadConsent;

  /// Backend base URL (not a secret; configurable for real devices).
  String serverBaseUrl;

  /// Opaque server cursor for incremental sync pulls; null = full pull.
  String? syncCursor;

  /// Epoch ms of the last successful sync; null = never synced.
  int? lastSyncAtMs;

  static ThemeMode _read(SharedPreferences prefs) =>
      switch (prefs.getString(_kThemeMode)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static bool _readBool(SharedPreferences prefs, String key) =>
      prefs.getBool(key) ?? false;

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == themeMode) return;
    themeMode = mode;
    notifyListeners();
    await _prefs.setString(_kThemeMode, mode.name);
  }

  Future<void> setAiProcessingConsent(bool value) async {
    if (value == aiProcessingConsent) return;
    aiProcessingConsent = value;
    notifyListeners();
    await _prefs.setBool(_kAiConsent, value);
  }

  Future<void> setCloudSyncEnabled(bool value) async {
    if (value == cloudSyncEnabled) return;
    cloudSyncEnabled = value;
    notifyListeners();
    await _prefs.setBool(_kCloudSyncEnabled, value);
  }

  Future<void> setJournalUploadConsent(bool value) async {
    if (value == journalUploadConsent) return;
    journalUploadConsent = value;
    notifyListeners();
    await _prefs.setBool(_kJournalUploadConsent, value);
  }

  Future<void> setServerBaseUrl(String value) async {
    final cleaned = value.trim().replaceAll(RegExp(r'/+$'), '');
    if (cleaned == serverBaseUrl) return;
    serverBaseUrl = cleaned;
    notifyListeners();
    await _prefs.setString(_kServerUrl, cleaned);
  }

  Future<void> setSyncCursor(String? cursor) async {
    syncCursor = cursor;
    if (cursor == null) {
      await _prefs.remove(_kSyncCursor);
    } else {
      await _prefs.setString(_kSyncCursor, cursor);
    }
  }

  Future<void> setLastSyncAt(DateTime time) async {
    lastSyncAtMs = time.toUtc().millisecondsSinceEpoch;
    notifyListeners();
    await _prefs.setInt(_kLastSyncAt, lastSyncAtMs!);
  }

  /// Clears sync bookkeeping (used when signing out or disabling sync).
  Future<void> clearSyncState() async {
    syncCursor = null;
    lastSyncAtMs = null;
    await _prefs.remove(_kSyncCursor);
    await _prefs.remove(_kLastSyncAt);
  }

  DateTime? get lastSyncAt => lastSyncAtMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          lastSyncAtMs!,
          isUtc: true,
        ).toLocal();
}
