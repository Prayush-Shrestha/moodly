import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted app preferences (theme mode) via shared_preferences.
class SettingsRepository extends ChangeNotifier {
  SettingsRepository._(this._prefs) : themeMode = _read(_prefs);

  static Future<SettingsRepository> load() async =>
      SettingsRepository._(await SharedPreferences.getInstance());

  static const String _kThemeMode = 'theme_mode';

  final SharedPreferences _prefs;

  ThemeMode themeMode;

  static ThemeMode _read(SharedPreferences prefs) =>
      switch (prefs.getString(_kThemeMode)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == themeMode) return;
    themeMode = mode;
    notifyListeners();
    await _prefs.setString(_kThemeMode, mode.name);
  }
}
