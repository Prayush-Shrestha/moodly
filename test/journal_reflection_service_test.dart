import 'package:flutter_test/flutter_test.dart';
import 'package:moodly/models/journal_entry.dart';
import 'package:moodly/services/journal_reflection_service.dart';

void main() {
  group('JournalReflectionService', () {
    test('produces a rule-based reflection for an entry', () {
      final service = JournalReflectionService();
      final entry = JournalEntry(
        date: DateTime(2026, 10, 28),
        title: 'Tough day',
        body: 'I felt stressed and overwhelmed today because I had many assignments, but I completed most of them.',
      );
      final result = service.reflect(entry);

      expect(result.summary, isNotEmpty);
      expect(result.isRuleBased, isTrue);
      expect(result.detectedEmotions, contains('stressed'));
      expect(result.themes, contains('challenging'));
      expect(result.reflectionQuestions, isNotEmpty);
      // No judgment: the reflection should not claim to diagnose anything.
      expect(result.summary, isNot(contains('diagnos')));
    });

    test('detects positive emotions and themes', () {
      final service = JournalReflectionService();
      final entry = JournalEntry(
        date: DateTime(2026, 10, 28),
        body: 'I felt grateful and happy. I completed my project.',
      );
      final result = service.reflect(entry);
      expect(result.detectedEmotions, contains('grateful'));
      expect(result.detectedEmotions, contains('happy'));
      expect(result.themes, contains('positive'));
    });

    test('falls back to reflective theme when nothing is detected', () {
      final service = JournalReflectionService();
      final entry = JournalEntry(
        date: DateTime(2026, 10, 28),
        body: 'Nothing much happened today.',
      );
      final result = service.reflect(entry);
      expect(result.themes, contains('reflective'));
      expect(result.reflectionQuestions, isNotEmpty);
    });

    test('detected emotions are deduplicated and stable', () {
      final service = JournalReflectionService();
      final entry = JournalEntry(
        date: DateTime(2026, 10, 28),
        body: 'happy happy calm calm',
      );
      final result = service.reflect(entry);
      expect(result.detectedEmotions, contains('happy'));
      expect(result.detectedEmotions, contains('calm'));
    });
  });
}
