import 'package:moodly/models/insight_card.dart';
import 'package:moodly/services/mood_analytics_service.dart';
import 'package:moodly/services/mood_pattern_service.dart';

/// Turns analytics and detected patterns into displayable insight cards.
///
/// Insights are only produced when there is enough supporting data; empty or
/// sparse datasets yield a helpful message rather than invented conclusions.
class InsightGenerationService {
  InsightGenerationService();

  /// Builds insight cards from [analytics] and [patterns].
  List<InsightCard> generateInsights(
    MoodAnalytics analytics,
    List<MoodPattern> patterns,
  ) {
    final cards = <InsightCard>[];

    for (final p in patterns) {
      cards.add(_patternToCard(p));
    }

    // When there is data but no strong pattern, offer a gentle starter insight.
    if (cards.isEmpty && analytics.totalEntries > 0) {
      cards.add(
        InsightCard(
          title: 'Getting to know your moods',
          description:
              'You have ${analytics.totalEntries} check-in${analytics.totalEntries == 1 ? '' : 's'} recorded. Keep checking in daily for clearer patterns.',
          type: InsightType.consistency,
          evidence:
              '${analytics.totalEntries} total entry${analytics.totalEntries == 1 ? '' : 's'}.',
          confidence: InsightConfidence.low,
          dataPointCount: analytics.totalEntries,
        ),
      );
    }

    return cards;
  }

  InsightCard _patternToCard(MoodPattern p) {
    return InsightCard(
      title: p.title,
      description: p.description,
      type: _toType(p.type),
      evidence: p.evidence,
      dateRangeStart: p.rangeStart,
      dateRangeEnd: p.rangeEnd,
      dataPointCount: p.dataPointCount,
      confidence: _toConfidence(p.confidence),
      isRuleBased: true,
    );
  }

  InsightType _toType(MoodPatternType t) {
    switch (t) {
      case MoodPatternType.mood:
        return InsightType.mood;
      case MoodPatternType.energy:
        return InsightType.energy;
      case MoodPatternType.emotion:
        return InsightType.emotion;
      case MoodPatternType.consistency:
      case MoodPatternType.streak:
      case MoodPatternType.gap:
        return InsightType.consistency;
    }
  }

  InsightConfidence _toConfidence(double c) {
    if (c >= 0.75) return InsightConfidence.high;
    if (c >= 0.55) return InsightConfidence.medium;
    return InsightConfidence.low;
  }
}
