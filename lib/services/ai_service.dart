import 'package:moodly/models/journal_entry.dart';
import 'package:moodly/services/journal_reflection_service.dart';

/// Abstraction for AI-powered features so Moodly can switch between a local
/// rule-based implementation and a future remote AI provider without touching
/// the UI.
abstract class AiService {
  /// Generates a reflection for [entry]. Must not send data anywhere without
  /// explicit user consent.
  Future<JournalReflectionResult> generateReflection(JournalEntry entry);

  /// True when reflections are produced locally by rules (Phase 2).
  bool get isRuleBased;
}

/// Local, offline rule-based implementation of [AiService]. No network, no
/// API keys, no personal data leaves the device.
class LocalAiService implements AiService {
  LocalAiService(this._reflectionService);

  final JournalReflectionService _reflectionService;

  @override
  bool get isRuleBased => true;

  @override
  Future<JournalReflectionResult> generateReflection(JournalEntry entry) async {
    return _reflectionService.reflect(entry);
  }
}

/// Stub for a future remote AI provider.
///
/// Moodly does not ship a remote AI integration in Phase 2. Using this service
/// throws a clear error rather than pretending AI is running.
class RemoteAiService implements AiService {
  @override
  bool get isRuleBased => false;

  @override
  Future<JournalReflectionResult> generateReflection(JournalEntry entry) async {
    throw UnsupportedError(
      'Remote AI is not configured. Moodly uses local rule-based reflections '
      'in Phase 2 and never sends journal entries to an external service '
      'without explicit consent.',
    );
  }
}
