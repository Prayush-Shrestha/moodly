/// A reflection generated for a standalone [JournalEntry].
///
/// Reflections are produced locally by a rule-based service (Phase 2). They
/// are stored so they survive a restart and can be regenerated on demand.
/// Deleting the parent journal entry cascades and removes the reflection.
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

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'journal_entry_id': journalEntryId,
    'summary': summary,
    'detected_emotions': detectedEmotions.join(','),
    'themes': themes.join(','),
    'reflection_questions': reflectionQuestions.join(','),
    'is_rule_based': isRuleBased ? 1 : 0,
    'created_at': createdAt.toUtc().millisecondsSinceEpoch,
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
  };
}
