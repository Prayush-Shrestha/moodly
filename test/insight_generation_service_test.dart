import 'package:flutter_test/flutter_test.dart';
import 'package:moodly/models/mood.dart';
import 'package:moodly/models/mood_entry.dart';
import 'package:moodly/models/insight_card.dart';
import 'package:moodly/services/insight_generation_service.dart';
import 'package:moodly/services/mood_analytics_service.dart';
import 'package:moodly/services/mood_pattern_service.dart';

void main() {
  group('InsightGenerationService', () {
    test('returns no cards when there is no data', () {
      final service = InsightGenerationService();
      final analytics = MoodAnalyticsService().analyzeAll(const []);
      final cards = service.generateInsights(analytics, const []);
      expect(cards, isEmpty);
    });

    test('returns a starter insight when data exists but no patterns', () {
      final service = InsightGenerationService();
      final analytics = MoodAnalyticsService().analyzeAll([
        MoodEntry(date: DateTime(2026, 10, 28), mood: Mood.okay, energy: 3),
      ]);
      final cards = service.generateInsights(analytics, const []);
      expect(cards, hasLength(1));
      expect(cards.first.title, 'Getting to know your moods');
      expect(cards.first.isRuleBased, isTrue);
      expect(cards.first.confidence, InsightConfidence.low);
    });

    test('converts patterns into cards with evidence and confidence', () {
      final service = InsightGenerationService();
      final analytics = MoodAnalyticsService().analyzeAll([
        MoodEntry(date: DateTime(2026, 10, 26), mood: Mood.great, energy: 5),
        MoodEntry(date: DateTime(2026, 10, 27), mood: Mood.great, energy: 4),
      ]);
      final patterns = MoodPatternService().detectPatterns(
        analytics,
        analytics.entries,
        today: DateTime(2026, 10, 28),
      );
      final cards = service.generateInsights(analytics, patterns);
      expect(cards, isNotEmpty);
      for (final card in cards) {
        expect(card.title, isNotEmpty);
        expect(card.description, isNotEmpty);
        expect(card.evidence, isNotEmpty);
        expect(card.isRuleBased, isTrue);
      }
    });

    test('cards carry the data range when provided', () {
      final service = InsightGenerationService();
      final analytics = MoodAnalyticsService().analyzeAll([
        MoodEntry(date: DateTime(2026, 10, 26), mood: Mood.great, energy: 5),
      ]);
      final patterns = [
        MoodPattern(
          title: 'Streak',
          description: '3 days in a row.',
          evidence: '3 consecutive days.',
          type: MoodPatternType.streak,
          confidence: 0.9,
          rangeStart: DateTime(2026, 10, 26),
          rangeEnd: DateTime(2026, 10, 28),
          dataPointCount: 3,
        ),
      ];
      final cards = service.generateInsights(analytics, patterns);
      expect(cards, hasLength(1));
      expect(cards.first.dateRangeStart, DateTime(2026, 10, 26));
      expect(cards.first.dateRangeEnd, DateTime(2026, 10, 28));
      expect(cards.first.dataPointCount, 3);
    });
  });
}
