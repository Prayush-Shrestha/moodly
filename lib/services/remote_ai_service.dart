import '../core/network/api_client.dart';
import '../repositories/settings_repository.dart';
import 'auth_service.dart';
import 'journal_reflection_service.dart';
import 'ai_service.dart';
import '../models/journal_entry.dart';

/// Real remote AI implementation backed by the FastAPI server.
///
/// The backend does the provider orchestration, validation and safety checks;
/// this client only transports one journal entry per call — and only after
/// the user's AI-processing consent is stored locally ([SettingsRepository]
/// gate, checked by the caller/routing service).
class RemoteAiService implements AiService {
  RemoteAiService({
    required this._api,
    required this._auth,
    required this._settings,
  });

  final ApiClient _api;
  final AuthService _auth;
  final SettingsRepository _settings;

  @override
  bool get isRuleBased => false;

  /// True when this device is actually able to call the backend AI: signed in
  /// AND the user enabled AI processing consent. Never pretends to be ready.
  bool get isAvailable => _auth.isSignedIn && _settings.aiProcessingConsent;

  @override
  Future<JournalReflectionResult> generateReflection(JournalEntry entry) async {
    if (!isAvailable) {
      throw const ApiException(
        message:
            'Remote AI is not enabled. Sign in and enable AI processing '
            'in Privacy settings, or use local reflections.',
      );
    }
    final payload = await _api.post(
      '/ai/reflection',
      body: {
        'journal_body': entry.body,
        'journal_title': entry.title,
        'entry_date': _dateKey(entry.date),
        'mood': null,
        'consent_given': true,
      },
    );
    return _resultFromPayload(payload);
  }

  /// Fetches the backend's AI mode (used by the connection screen).
  Future<AiStatus> fetchStatus() async {
    final payload = await _api.get('/ai/status');
    return AiStatus(
      aiEnabled: payload['ai_enabled'] == true,
      provider: payload['provider']?.toString() ?? 'none',
      mode: payload['mode']?.toString() ?? 'local_rules',
    );
  }

  static JournalReflectionResult _resultFromPayload(
    Map<String, Object?> payload,
  ) {
    final source = payload['source']?.toString() ?? 'local_rules';
    return JournalReflectionResult(
      summary: payload['summary']?.toString() ?? '',
      detectedEmotions: _stringList(payload['explicit_emotions']),
      explicitEmotions: _stringList(payload['explicit_emotions']),
      inferredEmotions: _stringList(payload['inferred_emotions']),
      themes: _stringList(payload['themes']),
      positiveObservations: _stringList(payload['positive_observations']),
      challenges: _stringList(payload['challenges']),
      reflectionQuestions: _stringList(payload['reflection_questions']),
      isRuleBased: source == 'local_rules',
      provider: source,
    );
  }

  static List<String> _stringList(Object? raw) =>
      raw is List ? raw.map((e) => e.toString()).toList() : const [];

  static String _dateKey(DateTime date) {
    final local = DateTime(date.year, date.month, date.day);
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

/// AI provider status reported by the backend.
class AiStatus {
  const AiStatus({
    required this.aiEnabled,
    required this.provider,
    required this.mode,
  });

  final bool aiEnabled;
  final String provider;

  /// `remote_ai` or `local_rules`.
  final String mode;
}
