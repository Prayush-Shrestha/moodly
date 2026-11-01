"""Strict validation of AI responses.

Everything the model returns is untrusted: it may be malformed, truncated,
over-long, or contain junk. This parser normalises to safe shapes, enforces
limits, and raises AiResponseError when the payload cannot be salvaged.
"""

from __future__ import annotations

import json
import re
from typing import Any

from app.schemas.ai import InsightCard, ReflectionResponse
from app.services.ai.provider import AiResponseError

MAX_SUMMARY = 1200
MAX_LIST_ITEMS = 8
MAX_TEXT_ITEM = 400
MAX_QUESTIONS = 3
MAX_INSIGHTS = 6

_Q_MARK = ("?", "？")
_SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s+")


def parse_json_object(raw: str | dict[str, Any]) -> dict[str, Any]:
    """Accept a JSON object from the model, tolerating ``` fences/prose."""
    if isinstance(raw, dict):
        return raw
    text = raw.strip()
    # Strip common markdown fences.
    if text.startswith("```"):
        text = re.sub(r"^```[a-zA-Z]*\n?", "", text)
        text = re.sub(r"\n?```$", "", text).strip()
    # Fall back to the first {...} block when prose surrounds the JSON.
    if not text.startswith("{"):
        start = text.find("{")
        end = text.rfind("}")
        if start == -1 or end == -1 or end <= start:
            raise AiResponseError("AI response did not contain a JSON object")
        text = text[start : end + 1]
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise AiResponseError("AI response was not valid JSON") from exc
    if not isinstance(data, dict):
        raise AiResponseError("AI response JSON was not an object")
    return data


def _clean_str(value: Any, limit: int = MAX_TEXT_ITEM) -> str:
    if not isinstance(value, str):
        return ""
    text = " ".join(value.split())
    return text[:limit].strip()


def _clean_list(value: Any, limit_items: int = MAX_LIST_ITEMS, limit_text: int = MAX_TEXT_ITEM) -> list[str]:
    if not isinstance(value, list):
        return []
    seen: list[str] = []
    for item in value:
        text = _clean_str(item, limit_text)
        if text and text.lower() not in {s.lower() for s in seen}:
            seen.append(text)
        if len(seen) >= limit_items:
            break
    return seen


def _clean_questions(value: Any) -> list[str]:
    items = _clean_list(value, limit_items=MAX_QUESTIONS)
    # Ensure questions actually read as questions.
    fixed: list[str] = []
    for item in items:
        if not item.endswith(_Q_MARK):
            item = item.rstrip(". ") + "?" if item else ""
        if item:
            fixed.append(item)
    return fixed[:MAX_QUESTIONS]


def _split_emotions(raw: Any) -> tuple[list[str], list[str]]:
    """Return (explicit, inferred) with sensible fallbacks."""
    explicit = _clean_list(raw.get("explicit_emotions"))
    inferred = _clean_list(raw.get("inferred_emotions"))
    if not explicit and not inferred:
        # Older/simpler models might emit "emotions" only.
        explicit = _clean_list(raw.get("emotions"))
    return explicit, inferred


def parse_reflection(data: dict[str, Any], source: str) -> ReflectionResponse:
    """Validate a reflection payload; raises AiResponseError when unusable."""
    summary = _clean_str(data.get("summary"), MAX_SUMMARY)
    if len(summary) < 10:
        raise AiResponseError("AI reflection summary was missing or too short")

    explicit, inferred = _split_emotions(data)
    themes = _clean_list(data.get("themes"))
    positive = _clean_list(data.get("positive_observations"))
    challenges = _clean_list(data.get("challenges"))
    questions = _clean_questions(data.get("reflection_questions"))
    if len(questions) != MAX_QUESTIONS:
        raise AiResponseError("AI reflection did not produce exactly 3 questions")

    return ReflectionResponse(
        summary=summary,
        explicit_emotions=explicit,
        inferred_emotions=inferred,
        themes=themes,
        positive_observations=positive,
        challenges=challenges,
        reflection_questions=questions,
        source=source,
        disclaimer_shown=True,
    )


def parse_insights(data: dict[str, Any], source: str) -> list[InsightCard]:
    raw_cards = data.get("insights")
    if not isinstance(raw_cards, list):
        raise AiResponseError("AI insights payload was malformed")
    cards: list[InsightCard] = []
    for raw in raw_cards:
        if not isinstance(raw, dict):
            continue
        title = _clean_str(raw.get("title"), 120)
        body = _clean_str(raw.get("body"), 900)
        basis = _clean_str(raw.get("data_basis"), 300)
        if title and body and basis:
            cards.append(InsightCard(title=title, body=body, icon=None, data_basis=basis))
        if len(cards) >= MAX_INSIGHTS:
            break
    if not cards:
        raise AiResponseError("AI insights payload contained no usable cards")
    return cards


def parse_report_narrative(data: dict[str, Any], source: str) -> tuple[str, list[str]]:
    narrative = _clean_str(data.get("narrative"), 2600)
    if len(narrative) < 20:
        raise AiResponseError("AI report narrative was missing or too short")
    questions = _clean_questions(data.get("reflection_questions"))
    return narrative, questions
