import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/journal_entry.dart';
import '../models/mood_entry.dart';
import '../repositories/journal_repository.dart';
import '../repositories/mood_repository.dart';

/// Result of a data export.
class ExportResult {
  const ExportResult({
    required this.json,
    required this.savedPath,
    required this.shared,
  });

  /// The full JSON payload (also handy for tests).
  final String json;

  /// Where the `.json` file was written on the device.
  final String savedPath;

  /// Whether the OS share sheet reported success.
  final bool shared;
}

/// Builds and shares a JSON backup of all user data.
class ExportService {
  ExportService({
    required MoodRepository moodRepository,
    required JournalRepository journalRepository,
  }) : _moods = moodRepository,
       _journals = journalRepository;

  final MoodRepository _moods;
  final JournalRepository _journals;

  /// Pure JSON payload — includes export metadata plus every mood and journal
  /// entry. Safe to call anywhere (used by tests).
  Future<String> buildJson({
    List<MoodEntry>? moodEntries,
    List<JournalEntry>? journalEntries,
    DateTime? exportedAt,
  }) async {
    final moods = moodEntries ?? await _moods.getAll();
    final journals = journalEntries ?? await _journals.getAll();
    final timestamp = exportedAt ?? DateTime.now();

    final payload = <String, Object?>{
      'app': 'Moodly',
      'tagline': 'Your Daily Mood',
      'schemaVersion': 1,
      'exportedAt': timestamp.toIso8601String(),
      'exportedAtLocal': DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp),
      'counts': {
        'moodEntries': moods.length,
        'journalEntries': journals.length,
      },
      'moodEntries': moods.map((e) => e.toJson()).toList(),
      'journalEntries': journals.map((e) => e.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Writes the JSON to a temporary file and opens the OS share sheet so the
  /// user can save it anywhere (cloud drive, email, files app, ...).
  Future<ExportResult> exportAll() async {
    final json = await buildJson();
    final timestamp = DateFormat('yyyyMMdd-HHmm').format(DateTime.now());
    final fileName = 'moodly-export-$timestamp.json';

    final dir = await getTemporaryDirectory();
    final filePath = p.join(dir.path, fileName);
    final file = File(filePath);
    await file.writeAsString(json, flush: true);

    var shared = false;
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          title: 'Moodly data export',
          text: 'Your Moodly data backup (mood check-ins and journal entries).',
        ),
      );
      shared = result.status == ShareResultStatus.success;
    } catch (_) {
      // The file is still written even if sharing is unavailable on this
      // device; the caller reports the saved path.
      shared = false;
    }
    return ExportResult(json: json, savedPath: file.path, shared: shared);
  }

  /// Shares arbitrary plain text (e.g. a generated report) via the OS share
  /// sheet. Returns whether the share flow completed.
  Future<bool> shareText(String text, {String title = 'Moodly'}) async {
    try {
      final result = await SharePlus.instance.share(
        ShareParams(text: text, title: title),
      );
      return result.status == ShareResultStatus.success;
    } catch (_) {
      return false;
    }
  }
}
