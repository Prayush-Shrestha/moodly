import 'package:flutter/material.dart';

import 'core/database/app_database.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';
import 'repositories/journal_reflection_repository.dart';
import 'repositories/journal_repository.dart';
import 'repositories/mood_repository.dart';
import 'repositories/settings_repository.dart';
import 'services/ai_service.dart';
import 'services/export_service.dart';
import 'services/journal_reflection_service.dart';

/// Root widget. Owns the database/repositories and exposes them to the tree
/// through [AppServices], which also makes widget tests injectable.
class MoodlyApp extends StatefulWidget {
  const MoodlyApp({
    super.key,
    required this.settingsRepository,
    this.database,
    this.splashMinDisplay = const Duration(milliseconds: 650),
  });

  final SettingsRepository settingsRepository;

  /// Injectable for tests; defaults to the on-device SQLite database.
  final AppDatabase? database;

  /// Minimum splash visibility; tests pass [Duration.zero].
  final Duration splashMinDisplay;

  @override
  State<MoodlyApp> createState() => _MoodlyAppState();
}

class _MoodlyAppState extends State<MoodlyApp> {
  late final AppDatabase _database;
  late final MoodRepository _moodRepository;
  late final JournalRepository _journalRepository;
  late final JournalReflectionRepository _journalReflectionRepository;
  late final ExportService _exportService;
  late final AiService _aiService;

  @override
  void initState() {
    super.initState();
    _database = widget.database ?? AppDatabase();
    _moodRepository = MoodRepository(_database);
    _journalRepository = JournalRepository(_database);
    _journalReflectionRepository = JournalReflectionRepository(_database);
    _exportService = ExportService(
      moodRepository: _moodRepository,
      journalRepository: _journalRepository,
    );
    _aiService = LocalAiService(JournalReflectionService());
  }

  @override
  Widget build(BuildContext context) {
    return AppServices(
      database: _database,
      moodRepository: _moodRepository,
      journalRepository: _journalRepository,
      journalReflectionRepository: _journalReflectionRepository,
      exportService: _exportService,
      aiService: _aiService,
      settingsRepository: widget.settingsRepository,
      child: ListenableBuilder(
        listenable: widget.settingsRepository,
        builder: (context, _) => MaterialApp(
          title: 'Moodly',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: widget.settingsRepository.themeMode,
          home: SplashScreen(
            initialization: _database.open().then((_) {}),
            minDisplay: widget.splashMinDisplay,
          ),
        ),
      ),
    );
  }
}

/// Provides repositories and services to the widget tree without a state
/// management dependency.
class AppServices extends InheritedWidget {
  const AppServices({
    super.key,
    required this.database,
    required this.moodRepository,
    required this.journalRepository,
    required this.journalReflectionRepository,
    required this.exportService,
    required this.aiService,
    required this.settingsRepository,
    required super.child,
  });

  final AppDatabase database;
  final MoodRepository moodRepository;
  final JournalRepository journalRepository;
  final JournalReflectionRepository journalReflectionRepository;
  final ExportService exportService;
  final AiService aiService;
  final SettingsRepository settingsRepository;

  /// Reads the services without registering a rebuild dependency (the
  /// services are created once and live for the whole app), so it is safe to
  /// call from `initState`, `didChangeDependencies`, and `build`.
  static AppServices of(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<AppServices>();
    assert(element != null, 'AppServices not found in widget tree');
    return element!.widget as AppServices;
  }

  @override
  bool updateShouldNotify(AppServices oldWidget) =>
      database != oldWidget.database ||
      moodRepository != oldWidget.moodRepository ||
      journalRepository != oldWidget.journalRepository ||
      journalReflectionRepository != oldWidget.journalReflectionRepository ||
      exportService != oldWidget.exportService ||
      aiService != oldWidget.aiService ||
      settingsRepository != oldWidget.settingsRepository;
}
