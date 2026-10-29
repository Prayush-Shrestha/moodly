import '../core/utils/date_utils.dart';

/// A standalone journal entry (free-form writing, any number per day).
class JournalEntry {
  JournalEntry({
    this.id,
    required DateTime date,
    required String body,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : date = AppDates.dateOnly(date),
       body = _validateBody(body),
       title = (title == null || title.trim().isEmpty) ? null : title.trim(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  /// Database primary key; `null` before the entry has been persisted.
  final int? id;

  /// Local calendar day the entry belongs to.
  final DateTime date;

  /// Optional short title.
  final String? title;

  /// Main content; at least one non-whitespace character is required.
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;

  static String _validateBody(String body) {
    if (body.trim().isEmpty) {
      throw ArgumentError.value(body, 'body', 'Journal body cannot be empty');
    }
    return body.trimRight();
  }

  /// Display title falls back to a neutral placeholder.
  String get displayTitle => title ?? 'Journal entry';

  /// First line of the body, used as a list preview.
  String get preview {
    final firstLine = body.trim().split('\n').first;
    return firstLine.length <= 90
        ? firstLine
        : '${firstLine.substring(0, 90)}…';
  }

  JournalEntry copyWith({
    int? id,
    DateTime? date,
    String? title,
    bool clearTitle = false,
    String? body,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return JournalEntry(
      id: id ?? this.id,
      date: date ?? this.date,
      title: clearTitle ? null : (title ?? this.title),
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Map representation for SQLite (matches the `journal_entries` schema).
  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'date': AppDates.dateKey(date),
    'title': title,
    'body': body,
    'created_at': createdAt.toUtc().millisecondsSinceEpoch,
    'updated_at': updatedAt.toUtc().millisecondsSinceEpoch,
  };

  factory JournalEntry.fromMap(Map<String, Object?> map) {
    final createdMs = map['created_at'] as int?;
    final updatedMs = map['updated_at'] as int?;
    return JournalEntry(
      id: map['id'] as int?,
      date: AppDates.parseDateKey(map['date'] as String),
      title: map['title'] as String?,
      body: map['body'] as String,
      createdAt: createdMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              createdMs,
              isUtc: true,
            ).toLocal(),
      updatedAt: updatedMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              updatedMs,
              isUtc: true,
            ).toLocal(),
    );
  }

  /// JSON representation used by the data export.
  Map<String, Object?> toJson() => {
    'id': id,
    'date': AppDates.dateKey(date),
    'title': title,
    'body': body,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory JournalEntry.fromJson(Map<String, Object?> json) {
    final created = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final updated = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    return JournalEntry(
      id: json['id'] as int?,
      date: AppDates.parseDateKey(json['date'] as String),
      title: json['title'] as String?,
      body: (json['body'] as String?) ?? '',
      createdAt: created,
      updatedAt: updated,
    );
  }

  /// True when this entry matches [query] in its title or body.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return displayTitle.toLowerCase().contains(q) ||
        body.toLowerCase().contains(q);
  }
}
