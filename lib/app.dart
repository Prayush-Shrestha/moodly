import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'core/database/app_database.dart';
import 'core/network/api_client.dart';
import 'core/network/token_store.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';
import 'repositories/journal_reflection_repository.dart';
import 'repositories/journal_repository.dart';
import 'repositories/mood_repository.dart';
import 'repositories/report_repository.dart';
import 'repositories/settings_repository.dart';
import 'services/ai_service.dart';
import 'services/auth_service.dart';
import 'services/export_service.dart';
import 'services/journal_reflection_service.dart';
import 'services/report_service.dart';
import 'services/routing_ai_service.dart';
import 'services/remote_ai_service.dart';
import 'services/sync_service.dart';

/// Root widget. Owns the database/repositories and exposes them to the tree
/// through [AppServices], which also makes widget tests injectable.
class MoodlyApp extends StatefulWidget {
  const MoodlyApp({
    super.key,
    required this.settingsRepository,
    this.database,
    this.splashMinDisplay = const Duration(milliseconds: 650),
    this.tokenStore,
    this.httpClient,
  });

  final SettingsRepository settingsRepository;

  /// Injectable for tests; defaults to the on-device SQLite database.
  final AppDatabase? database;

  /// Minimum splash visibility; tests pass [Duration.zero].
  final Duration splashMinDisplay;

  /// Injectable for tests; defaults to platform-secure token storage.
  final TokenStore? tokenStore;

  /// Injectable for tests; defaults to a real HTTP client.
  final http.Client? httpClient;

  @override
  State<MoodlyApp> createState() => _MoodlyAppState();
}

class _MoodlyAppState extends State<MoodlyApp> {
  late final AppDatabase _database;
  late final MoodRepository _moodRepository;
  late final JournalRepository _journalRepository;
  late final JournalReflectionRepository _journalReflectionRepository;
  late final ReportRepository _reportRepository;
  late final ExportService _exportService;
  late final ApiClient _apiClient;
  late final AuthService _authService;
  late final SyncService _syncService;
  late final ReportService _reportService;
  late final RoutingAiService _aiService;

  @override
  void initState() {
    super.initState();
    _database = widget.database ?? AppDatabase();
    _moodRepository = MoodRepository(_database);
    _journalRepository = JournalRepository(_database);
    _journalReflectionRepository = JournalReflectionRepository(_database);
    _reportRepository = ReportRepository(_database);
    _exportService = ExportService(
      moodRepository: _moodRepository,
      journalRepository: _journalRepository,
    );
    _apiClient = ApiClient(
      baseUrl: widget.settingsRepository.serverBaseUrl,
      client: widget.httpClient,
      tokenStore: widget.tokenStore ?? FlutterSecureTokenStore(),
    );
    _authService = AuthService(
      api: _apiClient,
      tokenStore: widget.tokenStore ?? FlutterSecureTokenStore(),
      settings: widget.settingsRepository,
    );
    _syncService = SyncService(
      api: _apiClient,
      auth: _authService,
      settings: widget.settingsRepository,
      moods: _moodRepository,
      journals: _journalRepository,
      database: _database,
    );
    _reportService = ReportService(
      moodRepository: _moodRepository,
      reportRepository: _reportRepository,
      api: _apiClient,
      auth: _authService,
      settings: widget.settingsRepository,
    );
    _aiService = RoutingAiService(
      local: LocalAiService(JournalReflectionService()),
      remote: RemoteAiService(
        api: _apiClient,
        auth: _authService,
        settings: widget.settingsRepository,
      ),
    );
    // Restore any previous session in the background (offline-safe).
    unawaited(_authService.restoreSession());
    // Keep the base URL in sync with settings changes.
    widget.settingsRepository.addListener(() {
      _apiClient.baseUrl = widget.settingsRepository.serverBaseUrl;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppServices(
      database: _database,
      moodRepository: _moodRepository,
      journalRepository: _journalRepository,
      journalReflectionRepository: _journalReflectionRepository,
      reportRepository: _reportRepository,
      exportService: _exportService,
      apiClient: _apiClient,
      authService: _authService,
      syncService: _syncService,
      reportService: _reportService,
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
    required this.reportRepository,
    required this.exportService,
    required this.apiClient,
    required this.authService,
    required this.syncService,
    required this.reportService,
    required this.aiService,
    required this.settingsRepository,
    required super.child,
  });

  final AppDatabase database;
  final MoodRepository moodRepository;
  final JournalRepository journalRepository;
  final JournalReflectionRepository journalReflectionRepository;
  final ReportRepository reportRepository;
  final ExportService exportService;
  final ApiClient apiClient;
  final AuthService authService;
  final SyncService syncService;
  final ReportService reportService;
  final RoutingAiService aiService;
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
      reportRepository != oldWidget.reportRepository ||
      exportService != oldWidget.exportService ||
      apiClient != oldWidget.apiClient ||
      authService != oldWidget.authService ||
      syncService != oldWidget.syncService ||
      reportService != oldWidget.reportService ||
      aiService != oldWidget.aiService ||
      settingsRepository != oldWidget.settingsRepository;
}
