import 'dart:convert';

import '../core/utils/date_utils.dart';
import 'emotion.dart';
import 'mood.dart';

/// One daily mood check-in.
///
/// A [MoodEntry] is always tied to a local calendar day ([date], stored as
/// `yyyy-MM-dd`) and there is at most one entry per day. Notes are optional
/// and emotions may be empty.
class MoodEntry {
  MoodEntry({
    this.id,
    required DateTime date,
    required this.mood,
    this.emotions = const [],
    required int energy,
    this.note,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.clientId,
    this.syncedAt,
  }) : date = AppDates.dateOnly(date),
       energy = _validateEnergy(energy),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  /// Database primary key; `null` before the entry has been persisted.
  final int? id;

  /// Local calendar day this check-in belongs to (time-of-day stripped).
  final DateTime date;
  final Mood mood;
  final List<Emotion> emotions;

  /// Energy level, 1 (drained) … 5 (full of energy).
  final int energy;

  /// Optional reflection note.
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Stable id used for cloud sync (Phase 3). Generated on first save; never
  /// changes afterwards. `null` until the row has been persisted at least once
  /// (migration backfills older rows).
  final String? clientId;

  /// When this row was last accepted by the cloud account (`null` = pending).
  final DateTime? syncedAt;

  /// True when the row has local changes not yet acknowledged by the server.
  bool get needsSync => syncedAt == null;

  static int _validateEnergy(int energy) {
    if (energy < 1 || energy > 5) {
      throw ArgumentError.value(
        energy,
        'energy',
        'Energy must be between 1 and 5',
      );
    }
    return energy;
  }

  MoodEntry copyWith({
    int? id,
    DateTime? date,
    Mood? mood,
    List<Emotion>? emotions,
    int? energy,
    String? note,
    bool clearNote = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? clientId,
    bool clearClientId = false,
    DateTime? syncedAt,
    bool clearSyncedAt = false,
  }) {
    return MoodEntry(
      id: id ?? this.id,
      date: date ?? this.date,
      mood: mood ?? this.mood,
      emotions: emotions ?? this.emotions,
      energy: energy ?? this.energy,
      note: clearNote ? null : (note ?? this.note),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      clientId: clearClientId ? null : (clientId ?? this.clientId),
      syncedAt: clearSyncedAt ? null : (syncedAt ?? this.syncedAt),
    );
  }

  /// Map representation for SQLite (matches the `mood_entries` schema).
  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'date': AppDates.dateKey(date),
    'mood': mood.storageName,
    'emotions': serializeEmotions(emotions),
    'energy': energy,
    'note': note,
    'created_at': createdAt.toUtc().millisecondsSinceEpoch,
    'updated_at': updatedAt.toUtc().millisecondsSinceEpoch,
    'client_id': clientId,
    'synced_at': syncedAt?.toUtc().millisecondsSinceEpoch,
  };

  factory MoodEntry.fromMap(Map<String, Object?> map) {
    final createdMs = map['created_at'] as int?;
    final updatedMs = map['updated_at'] as int?;
    final syncedMs = map['synced_at'] as int?;
    return MoodEntry(
      id: map['id'] as int?,
      date: AppDates.parseDateKey(map['date'] as String),
      mood: Mood.fromStorageName(map['mood'] as String?),
      emotions: parseEmotions(map['emotions'] as String?),
      energy: (map['energy'] as int?) ?? 3,
      note: map['note'] as String?,
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
      clientId: map['client_id'] as String?,
      syncedAt: syncedMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              syncedMs,
              isUtc: true,
            ).toLocal(),
    );
  }

  /// JSON representation used by the data export.
  Map<String, Object?> toJson() => {
    'id': id,
    'date': AppDates.dateKey(date),
    'mood': mood.storageName,
    'moodLabel': mood.label,
    'emotions': emotions.map((e) => e.storageName).toList(),
    'energy': energy,
    'note': note,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory MoodEntry.fromJson(Map<String, Object?> json) {
    final created = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final updated = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    final energyRaw = json['energy'];
    return MoodEntry(
      id: json['id'] as int?,
      date: AppDates.parseDateKey(json['date'] as String),
      mood: Mood.fromStorageName(json['mood'] as String?),
      emotions: _emotionsFromJson(json['emotions'] as List<Object?>?),
      energy: energyRaw is int ? energyRaw : 3,
      note: json['note'] as String?,
      createdAt: created,
      updatedAt: updated,
    );
  }

  /// Decodes a JSON-exported emotions list (array of storage names).
  static List<Emotion> _emotionsFromJson(List<Object?>? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return parseEmotions(raw.join(','));
  }

  String encodeToJsonString() => jsonEncode(toJson());
}
