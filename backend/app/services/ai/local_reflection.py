"""Backend mirror of the on-device rule-based reflection.

Kept intentionally close to the Flutter `JournalReflectionService` so users
see consistent behaviour whether the fallback runs on the device or on the
server (e.g. when an authenticated user triggers a remote call but no AI
provider is configured).
"""

from __future__ import annotations

from app.schemas.ai import ReflectionResponse

_SOURCE = "local_rules"

_EMOTION_KEYWORDS: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("calm", ("calm", "relaxed", "peaceful", "serene")),
    ("happy", ("happy", "joy", "glad", "delighted", "cheerful")),
    ("excited", ("excited", "thrilled", "pumped", "exhilarated")),
    ("grateful", ("grateful", "thankful", "gratitude", "appreciation")),
    ("motivated", ("motivated", "driven", "determined", "focused")),
    ("tired", ("tired", "exhausted", "weary", "drained", "fatigue")),
    ("stressed", ("stressed", "pressure", "overwhelmed", "stress")),
    ("anxious", ("anxious", "nervous", "worried", "unease")),
    ("sad", ("sad", "down", "upset", "unhappy", "miserable")),
    ("angry", ("angry", "mad", "furious", "annoyed", "frustrated")),
)

_CHALLENGING = (
    "difficult", "hard", "tough", "struggle", "problem",
    "overwhelmed", "stress", "busy", "workload", "assignments",
)
_POSITIVE = (
    "great", "good", "wonderful", "accomplished", "proud",
    "completed", "finished", "achieved", "success",
)


def local_reflection(
    body: str, title: str | None, entry_date: str, mood: str | None
) -> ReflectionResponse:
    lowered = (body or "").lower()

    detected = [
        label
        for label, keywords in _EMOTION_KEYWORDS
        if any(k in lowered for k in keywords)
    ]

    themes: list[str] = []
    if any(k in lowered for k in _CHALLENGING):
        themes.append("challenging")
    if any(k in lowered for k in _POSITIVE):
        themes.append("positive")
    if "tired" in detected or "stressed" in detected:
        themes.append("draining")
    if not themes:
        themes.append("reflective")

    questions = _build_questions(themes)

    summary = f'On {entry_date}, you wrote about "{title or "an untitled entry"}".'
    if [t for t in themes if t != "reflective"]:
        summary += " Themes included " + ", ".join(t for t in themes if t != "reflective") + "."
    else:
        summary += " Take a moment to reflect on what this day meant to you."

    positive = (
        ["The entry mentions something that went well or felt meaningful."]
        if "positive" in themes
        else []
    )
    challenges = (
        ["The entry mentions something that felt difficult or demanding."]
        if "challenging" in themes or "draining" in themes
        else []
    )

    return ReflectionResponse(
        summary=summary,
        explicit_emotions=detected,
        inferred_emotions=[],
        themes=themes,
        positive_observations=positive,
        challenges=challenges,
        reflection_questions=questions,
        source=_SOURCE,
        disclaimer_shown=True,
    )


def _build_questions(themes: list[str]) -> list[str]:
    questions: list[str] = []
    if "challenging" in themes:
        questions += [
            "What could make tomorrow feel more manageable?",
            "What support or resources do you have available?",
        ]
    if "positive" in themes:
        questions += [
            "What helped make today go well?",
            "How can you build on this momentum?",
        ]
    if "draining" in themes:
        questions.append("What would help you recharge?")
    if not questions:
        questions = ["What stood out most about today?", "How are you feeling right now?"]
    return questions[:3]
