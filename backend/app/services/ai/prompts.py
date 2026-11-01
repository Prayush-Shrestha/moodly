"""Prompt construction for AI features.

Privacy rule: prompts carry only what the specific feature strictly needs.
Reflection prompts include exactly one journal entry (requires explicit
consent). Insight/report prompts carry only aggregate statistics — never any
journal text.
"""

from __future__ import annotations

from app.schemas.ai import InsightAggregates

REFLECTION_SYSTEM = """\
You are Moodly's reflection assistant — a calm, non-judgmental writing companion.

Rules you MUST follow:
- Only report emotions the writer EXPLICITLY expressed; put anything you infer in "inferred_emotions" and only when clearly supported by the text. Never invent feelings, people, events or details.
- Never diagnose, never evaluate mental health, never suggest medication.
- Keep the tone gentle and curious, never clinical or cheerleading.
- The summary must be 2–3 sentences based only on the entry.
- "themes" are short nouns (max 3), "positive_observations" and "challenges" are 1–2 sentences each grounded in the text; use empty lists when absent from the entry.
- "reflection_questions" must be exactly 3 thoughtful questions about what was written.

Respond with ONLY a JSON object of this shape (no markdown fences, no commentary):
{
  "summary": "string",
  "explicit_emotions": ["string"],
  "inferred_emotions": ["string"],
  "themes": ["string"],
  "positive_observations": ["string"],
  "challenges": ["string"],
  "reflection_questions": ["string", "string", "string"]
}
"""

REFLECTION_USER = """\
Journal entry to reflect on:
Date: {date}
Title: {title}
Mood recorded that day: {mood}

Entry:
\"\"\"
{body}
\"\"\"

Remember: explicit vs inferred emotions must stay separate; only 3 questions.
"""


def reflection_prompt(
    body: str, title: str | None, date: str, mood: str | None
) -> str:
    return REFLECTION_USER.format(
        date=date,
        title=title or "(untitled)",
        mood=mood or "(not recorded)",
        body=body,
    )


INSIGHT_SYSTEM = """\
You are Moodly's insight writer. You receive ONLY aggregate statistics computed
from a person's own mood check-ins (counts, averages, streaks).

Rules:
- Every sentence must be traceable to the provided numbers; never invent
  statistics or claim causation ("causes", "because of", "you are") — describe
  patterns as observations ("on days you logged X, Y tended to be higher").
- Never diagnose or hint at medical conditions.
- If totals are small, say the data is limited and avoid firm conclusions.
- Return ONLY a JSON object:
{"insights": [{"title": "string", "body": "string", "data_basis": "string"}]}
"data_basis" explains in one clause which numbers support the insight (shown to the user).
"""

INSIGHT_USER = """\
Period: {label}  ({from_date} to {to_date})
Total check-ins: {total}
Mood distribution: {dist}
Most logged mood: {dominant}
Average energy (1-5): {energy}
Most frequent emotions: {emotions}
Days logged at least once (consistency): {consistent}
Current check-in streak: {streak} days

Write 2–4 short, gentle insight cards based strictly on these numbers.
"""

REPORT_SYSTEM = """\
You are Moodly's weekly/monthly report writer. You receive ONLY aggregate
statistics (no journal text, no personal details).

Rules:
- Base every statement on the numbers; never invent statistics or claim
  causation; no medical statements, ever.
- 3–5 sentences, gentle and reflective in tone.
- Then write 3 reflection questions that connect the numbers to the person's
  own experience without assuming what happened.
- Return ONLY a JSON object:
{"narrative": "string", "reflection_questions": ["string", "string", "string"]}
"""

REPORT_USER = """\
Report period: {label}  ({from_date} to {to_date})
Total check-ins: {total}
Mood distribution: {dist}
Most logged mood: {dominant}
Average energy (1-5): {energy}
Most frequent emotions: {emotions}
Consistency: {consistent} of {span} days logged
Comparison with previous period: {comparison}
"""


def _dist_text(dist: dict[str, int]) -> str:
    return ", ".join(f"{k}={v}" for k, v in sorted(dist.items())) or "(none)"


def insight_prompt(a: InsightAggregates) -> str:
    return INSIGHT_USER.format(
        label=a.period_label,
        from_date=a.analysis_from,
        to_date=a.analysis_to,
        total=a.total_checkins,
        dist=_dist_text(a.mood_distribution),
        dominant=a.dominant_mood or "(none)",
        energy=(f"{a.average_energy:.1f}" if a.average_energy is not None else "(n/a)"),
        emotions=", ".join(a.top_emotions) or "(none)",
        consistent=a.consistent_days,
        streak=a.streak_days,
    )


def report_prompt(
    a: InsightAggregates, comparison: str | None, span_days: int
) -> str:
    return REPORT_USER.format(
        label=a.period_label,
        from_date=a.analysis_from,
        to_date=a.analysis_to,
        total=a.total_checkins,
        dist=_dist_text(a.mood_distribution),
        dominant=a.dominant_mood or "(none)",
        energy=(f"{a.average_energy:.1f}" if a.average_energy is not None else "(n/a)"),
        emotions=", ".join(a.top_emotions) or "(none)",
        consistent=a.consistent_days,
        span=span_days,
        comparison=comparison or "(no comparison — not enough data)",
    )
