"""Content-safety helpers for AI prompts and outputs.

Input side: journal text is wrapped and fenced, and the model is told it is
data, not instructions — mitigating prompt-injection ("ignore your rules and…").

Output side: responses are length-capped, control characters stripped, and
medical/diagnostic phrasing is detected. When detected, the output is
re-labelled in the UI disclaimer rather than silently shown (we never claim
clinical authority).
"""

from __future__ import annotations

import re
from dataclasses import dataclass

_MAX_INPUT_CHARS = 20000

# Phrases a reflection must never contain; if present the content is flagged
# and the caller appends an explicit "not medical advice" note (the app
# always shows a disclaimer; this triggers the stronger variant).
_DIAGNOSTIC_RE = re.compile(
    r"\b(depress(?:ion|ive|ed)|anxiety disorder|suicid(?:e|al)|bipolar|"
    r"ptsd|ocd|disorder|diagnos(?:e|is|ed)|therapist|medication|"
    r"you (?:have|are) (?:depressed|anxious))\b",
    re.IGNORECASE,
)

_CONTROL_CHARS = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")


@dataclass
class SafetyResult:
    text: str
    flagged_medical: bool = False


class AiSafetyService:
    """Stateless guardrails; safe to share across requests."""

    def prepare_journal_text(self, body: str, title: str | None = None) -> str:
        """Sanitise untrusted user text before it enters a prompt."""
        text = _CONTROL_CHARS.sub("", body or "").strip()[:_MAX_INPUT_CHARS]
        title_clean = _CONTROL_CHARS.sub("", (title or "").strip())[:200]
        return f"{title_clean}\n\n{text}".strip()

    def contains_injection_attempt(self, body: str) -> bool:
        """Cheap heuristic check; not a guarantee — prompts are also hardened."""
        lowered = (body or "").lower()
        markers = (
            "ignore previous instructions",
            "ignore all previous",
            "disregard your instructions",
            "you are now",
            "system prompt:",
            "reveal your instructions",
            "pretend you are",
            "developer mode",
        )
        return any(marker in lowered for marker in markers)

    def inspect_output(self, text: str) -> SafetyResult:
        cleaned = _CONTROL_CHARS.sub("", text or "").strip()
        flagged = bool(_DIAGNOSTIC_RE.search(cleaned))
        return SafetyResult(text=cleaned, flagged_medical=flagged)

    def inspect_output_list(self, texts: list[str]) -> SafetyResult:
        joined = " ".join(texts)
        cleaned = self.inspect_output(joined)
        return SafetyResult(text=cleaned.text, flagged_medical=cleaned.flagged_medical)
