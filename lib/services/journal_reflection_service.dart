import 'package:moodly/core/utils/formatters.dart';
import 'package:moodly/models/journal_entry.dart';

/// Result of a journal reflection, produced by a local rule-based service or
/// by the remote AI backend (Phase 3).
class JournalReflectionResult {
  const JournalReflectionResult({
    required this.summary,
    required this.detectedEmotions,
    required this.themes,
    required this.reflectionQuestions,
    required this.isRuleBased,
    this.positiveObservations = const [],
    this.challenges = const [],
    this.explicitEmotions = const [],
    this.inferredEmotions = const [],
    this.provider = 'local_rules',
  });

  /// Short, non-judgmental summary of the entry.
  final String summary;

  /// Emotion labels detected in the entry text.
  final List<String> detectedEmotions;

  /// Detected themes, e.g. `challenging`, `positive`.
  final List<String> themes;

  /// Suggested reflection questions.
  final List<String> reflectionQuestions;

  /// True when produced by the local rule-based service.
  final bool isRuleBased;

  /// Positive observations explicitly present in the text (AI reflections).
  final List<String> positiveObservations;

  /// Challenges explicitly mentioned in the text (AI reflections).
  final List<String> challenges;

  /// Emotions the writer explicitly expressed (AI reflections).
  final List<String> explicitEmotions;

  /// Emotions inferred by the model, kept separate from explicit ones.
  final List<String> inferredEmotions;

  /// `local_rules` or `ai:<provider>`.
  final String provider;
}

/// Rule-based journal reflection service.
///
/// No external AI is involved. The reflection is a transparent, explainable
/// scan of the user's own words and may be inaccurate — it is clearly labeled
/// as rule-based and offered optionally.
class JournalReflectionService {
  JournalReflectionService();

  /// Reflects on [entry] without storing anything. Callers decide whether to
  /// persist the result.
  JournalReflectionResult reflect(JournalEntry entry, {DateTime? now}) {
    final body = entry.body.toLowerCase();
    final detected = _detectEmotions(body);
    final themes = _detectThemes(body, detected);
    final questions = _buildQuestions(themes, detected);
    final summary = _buildSummary(entry, themes);
    return JournalReflectionResult(
      summary: summary,
      detectedEmotions: detected,
      themes: themes,
      reflectionQuestions: questions,
      isRuleBased: true,
    );
  }

  List<String> _detectEmotions(String body) {
    final found = <String>[];
    final checks = const [
      ('calm', ['calm', 'relaxed', 'peaceful', 'serene']),
      ('happy', ['happy', 'joy', 'glad', 'delighted', 'cheerful']),
      ('excited', ['excited', 'thrilled', 'pumped', 'exhilarated']),
      ('grateful', ['grateful', 'thankful', 'gratitude', 'appreciation']),
      ('motivated', ['motivated', 'driven', 'determined', 'focused']),
      ('tired', ['tired', 'exhausted', 'weary', 'drained', 'fatigue']),
      ('stressed', ['stressed', 'pressure', 'overwhelmed', 'stress']),
      ('anxious', ['anxious', 'nervous', 'worried', 'unease']),
      ('sad', ['sad', 'down', 'upset', 'unhappy', 'miserable']),
      ('angry', ['angry', 'mad', 'furious', 'annoyed', 'frustrated']),
    ];
    for (final (label, keywords) in checks) {
      if (keywords.any((k) => body.contains(k))) {
        found.add(label);
      }
    }
    return found;
  }

  List<String> _detectThemes(String body, List<String> emotions) {
    final themes = <String>[];
    final challenging = [
      'difficult',
      'hard',
      'tough',
      'struggle',
      'problem',
      'overwhelmed',
      'stress',
      'busy',
      'assignments',
      'workload',
    ];
    final positive = [
      'great',
      'good',
      'wonderful',
      'accomplished',
      'proud',
      'completed',
      'finished',
      'achieved',
      'success',
    ];
    if (challenging.any((k) => body.contains(k))) themes.add('challenging');
    if (positive.any((k) => body.contains(k))) themes.add('positive');
    if (emotions.contains('tired') || emotions.contains('stressed')) {
      themes.add('draining');
    }
    if (themes.isEmpty) themes.add('reflective');
    return themes;
  }

  List<String> _buildQuestions(List<String> themes, List<String> emotions) {
    final q = <String>[];
    if (themes.contains('challenging')) {
      q.add('What could make tomorrow feel more manageable?');
      q.add('What support or resources do you have available?');
    }
    if (themes.contains('positive')) {
      q.add('What helped make today go well?');
      q.add('How can you build on this momentum?');
    }
    if (themes.contains('draining')) {
      q.add('What would help you recharge?');
    }
    if (q.isEmpty) {
      q.add('What stood out most about today?');
      q.add('How are you feeling right now?');
    }
    return q.take(3).toList();
  }

  String _buildSummary(JournalEntry entry, List<String> themes) {
    final themeList = themes.where((t) => t != 'reflective').join(', ');
    final date = Formatters.mediumDate(entry.date);
    final sentence1 = 'On $date, you wrote about "${entry.displayTitle}".';
    if (themeList.isNotEmpty) {
      return '$sentence1 Themes included $themeList.';
    }
    return '$sentence1 Take a moment to reflect on what this day meant to you.';
  }
}
