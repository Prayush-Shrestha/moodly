import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'repositories/settings_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load date symbols so DateFormat patterns work regardless of device locale
  // (Phase 1 ships an English-only UI).
  await initializeDateFormatting();

  final settings = await SettingsRepository.load();
  runApp(MoodlyApp(settingsRepository: settings));
}
