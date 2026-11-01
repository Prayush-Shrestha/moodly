/// A reflection generated for a standalone [JournalEntry].
///
/// Phase 2 produced rule-based reflections; Phase 3 adds AI-generated ones
/// from the backend provider. Deleting the parent journal entry cascades and
/// removes the reflection.
class JournalReflection {
  const JournalReflection({
    this.id,
    required this.journalEntryId,
    required this.summary,
    this.detectedEmotions = const [],
    this.themes = const [],
    this.reflectionQuestions = const [],
    this.isRuleBased = true,
    required this.createdAt,
    this.positiveObservations = const [],
    this.challenges = const [],
    this.explicitEmotions = const [],
    this.inferredEmotions = const [],
    this.provider = 'local_rules',
  });

  /// Database primary key; `null` before the reflection has been persisted.
  final int? id;

  /// The journal entry this reflection belongs to.
  final int journalEntryId;

  /// Short summary of the entry.
  final String summary;

  /// Emotion labels detected in the entry text (rule-based keyword scan).
  final List<String> detectedEmotions;

  /// Detected themes, e.g. `challenging`, `productive`.
  final List<String> themes;

  /// Suggested reflection questions.
  final List<String> reflectionQuestions;

  /// True when produced by the local rule-based service (not an external AI).
  final bool isRuleBased;

  final DateTime createdAt;

  /// Phase 3 (AI reflections): positive things explicitly present in the text.
  final List<String> positiveObservations;

  /// Phase 3 (AI reflections): challenges explicitly mentioned in the text.
  final List<String> challenges;

  /// Phase 3 (AI): emotions the writer EXPLICITLY expressed.
  final List<String> explicitEmotions;

  /// Phase 3 (AI): emotions the model inferred (clearly separated from
  /// explicitly expressed ones so the UI can label them honestly).
  final List<String> inferredEmotions;

  /// What produced this: `local_rules` or `ai:<provider>`.
  final String provider;

  /// Effective explicit-emotion list: AI reflections keep explicit/inferred
  /// separate; rule-based ones fall back to the Phase 2 keyword scan.
  List<String> get allEmotions =>
      explicitEmotions.isNotEmpty ? explicitEmotions : detectedEmotions;

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'journal_entry_id': journalEntryId,
    'summary': summary,
    'detected_emotions': detectedEmotions.join(','),
    'themes': themes.join(','),
    'reflection_questions': reflectionQuestions.join(','),
    'is_rule_based': isRuleBased ? 1 : 0,
    'created_at': createdAt.toUtc().millisecondsSinceEpoch,
    'positive_observations': positiveObservations.join(','),
    'challenges': challenges.join(','),
    'explicit_emotions': explicitEmotions.join(','),
    'inferred_emotions': inferredEmotions.join(','),
    'provider': provider,
  };

  factory JournalReflection.fromMap(Map<String, Object?> map) {
    return JournalReflection(
      id: map['id'] as int?,
      journalEntryId: map['journal_entry_id'] as int,
      summary: map['summary'] as String,
      detectedEmotions: _parseList(map['detected_emotions'] as String?),
      themes: _parseList(map['themes'] as String?),
      reflectionQuestions: _parseList(map['reflection_questions'] as String?),
      isRuleBased: (map['is_rule_based'] as int?) == 1,
      createdAt: _parseTime(map['created_at']),
      positiveObservations: _parseList(map['positive_observations'] as String?),
      challenges: _parseList(map['challenges'] as String?),
      explicitEmotions: _parseList(map['explicit_emotions'] as String?),
      inferredEmotions: _parseList(map['inferred_emotions'] as String?),
      provider: (map['provider'] as String?) ?? 'local_rules',
    );
  }

  JournalReflection copyWith({
    int? id,
    int? journalEntryId,
    String? summary,
    List<String>? detectedEmotions,
    List<String>? themes,
    List<String>? reflectionQuestions,
    bool? isRuleBased,
    DateTime? createdAt,
    List<String>? positiveObservations,
    List<String>? challenges,
    List<String>? explicitEmotions,
    List<String>? inferredEmotions,
    String? provider,
  }) {
    return JournalReflection(
      id: id ?? this.id,
      journalEntryId: journalEntryId ?? this.journalEntryId,
      summary: summary ?? this.summary,
      detectedEmotions: detectedEmotions ?? this.detectedEmotions,
      themes: themes ?? this.themes,
      reflectionQuestions: reflectionQuestions ?? this.reflectionQuestions,
      isRuleBased: isRuleBased ?? this.isRuleBased,
      createdAt: createdAt ?? this.createdAt,
      positiveObservations: positiveObservations ?? this.positiveObservations,
      challenges: challenges ?? this.challenges,
      explicitEmotions: explicitEmotions ?? this.explicitEmotions,
      inferredEmotions: inferredEmotions ?? this.inferredEmotions,
      provider: provider ?? this.provider,
    );
  }

  static List<String> _parseList(String? stored) {
    if (stored == null || stored.trim().isEmpty) return const [];
    return stored.split(',').where((e) => e.trim().isNotEmpty).toList();
  }

  static DateTime _parseTime(Object? ms) {
    if (ms == null) return DateTime.now();
    return DateTime.fromMillisecondsSinceEpoch(
      ms as int,
      isUtc: true,
    ).toLocal();
  }

  /// JSON payload used for export/debug. Never sent anywhere automatically.
  Map<String, Object?> toJson() => {
    'id': id,
    'journalEntryId': journalEntryId,
    'summary': summary,
    'detectedEmotions': detectedEmotions,
    'themes': themes,
    'reflectionQuestions': reflectionQuestions,
    'isRuleBased': isRuleBased,
    'createdAt': createdAt.toIso8601String(),
    'positiveObservations': positiveObservations,
    'challenges': challenges,
    'explicitEmotions': explicitEmotions,
    'inferredEmotions': inferredEmotions,
    'provider': provider,
  };
}
