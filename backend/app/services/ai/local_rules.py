"""Deterministic, rule-based fallbacks used when no AI provider is configured
or when the provider fails. These never invent numbers: every sentence is
built from the aggregate statistics actually provided.
"""

from __future__ import annotations

from app.schemas.ai import InsightAggregates, InsightCard

_MOST_COMMON = (
    ("great", "You logged most of your check-ins as **Great**"),
    ("good", "You logged most of your check-ins as **Good**"),
    ("okay", "You logged most of your check-ins as **Okay**"),
    ("low", "You logged most of your check-ins as **Low**"),
    ("terrible", "You logged most of your check-ins as **Terrible**"),
)


def _dist_text(dist: dict[str, int]) -> str:
    return ", ".join(f"{k}: {v}" for k, v in sorted(dist.items()) if v > 0)


def local_insight_cards(a: InsightAggregates) -> list[InsightCard]:
    cards: list[InsightCard] = []
    if a.total_checkins == 0:
        return [
            InsightCard(
                title="Not enough data yet",
                body="No check-ins in this period — insights appear once you log a mood.",
                icon=None,
                data_basis="0 check-ins in range",
            )
        ]

    if a.dominant_mood:
        label = next(
            (text for mood, text in _MOST_COMMON if mood == a.dominant_mood),
            None,
        )
        if label:
            cards.append(
                InsightCard(
                    title="Most logged mood",
                    body=f"{label} across {a.total_checkins} check-ins this period.",
                    icon=None,
                    data_basis=f"mood distribution: {_dist_text(a.mood_distribution)}",
                )
            )

    if a.average_energy is not None:
        cards.append(
            InsightCard(
                title="Average energy",
                body=(
                    f"Your average logged energy was {a.average_energy:.1f} out of 5 "
                    f"over {a.total_checkins} check-ins."
                ),
                icon=None,
                data_basis=f"mean energy across {a.total_checkins} check-ins",
            )
        )

    if a.top_emotions:
        top = ", ".join(a.top_emotions[:3])
        cards.append(
            InsightCard(
                title="Recurring emotions",
                body=f"Emotions you logged most often: {top}.",
                icon=None,
                data_basis="emotion frequency counts",
            )
        )

    span_days = _span_days(a)
    if span_days > 0:
        cards.append(
            InsightCard(
                title="Check-in consistency",
                body=(
                    f"You checked in on {a.consistent_days} of the last {span_days} days "
                    f"(current streak: {a.streak_days} day{'s' if a.streak_days != 1 else ''})."
                ),
                icon=None,
                data_basis="check-in days vs period span",
            )
        )
    return cards[:6]


def _span_days(a: InsightAggregates) -> int:
    from datetime import date

    try:
        start = date.fromisoformat(a.analysis_from)
        end = date.fromisoformat(a.analysis_to)
    except ValueError:
        return 0
    return max(0, (end - start).days + 1)


def local_report_narrative(
    a: InsightAggregates, comparison: str | None
) -> tuple[str, list[str]]:
    if a.total_checkins == 0:
        return (
            "No check-ins were recorded in this period, so there is nothing to "
            "summarise yet. If you check in a few days this report will start "
            "to take shape.",
            ["Would you like to check in today?", "What would make checking in easier?"],
        )

    parts: list[str] = [
        f"Across {a.period_label} ({a.analysis_from} to {a.analysis_to}) you logged "
        f"{a.total_checkins} check-in{'s' if a.total_checkins != 1 else ''}."
    ]
    if a.dominant_mood:
        parts.append(f"Your most logged mood was {a.dominant_mood}.")
    if a.average_energy is not None:
        parts.append(f"Your average energy was {a.average_energy:.1f} out of 5.")
    if a.top_emotions:
        parts.append(f"Recurring emotions included {', '.join(a.top_emotions[:3])}.")
    if comparison:
        parts.append(comparison)
    narrative = " ".join(parts)

    questions = [
        "What do you think shaped your mood most during this period?",
        "Which of these numbers feels most true to your experience?",
        "What would you like to try next period?",
    ]
    return narrative, questions
