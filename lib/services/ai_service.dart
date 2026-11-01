import 'package:moodly/models/journal_entry.dart';
import 'package:moodly/services/journal_reflection_service.dart';

/// Abstraction for AI-powered features so Moodly can switch between a local
/// rule-based implementation and a remote AI provider without touching the
/// UI.
abstract class AiService {
  /// Generates a reflection for [entry]. Implementations must not send data
  /// anywhere without explicit user consent (checked by [RemoteAiService]).
  Future<JournalReflectionResult> generateReflection(JournalEntry entry);

  /// True when reflections are produced locally by rules (no external AI).
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
