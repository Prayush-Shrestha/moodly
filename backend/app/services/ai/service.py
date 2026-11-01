"""`AiService` facade: provider orchestration, safety, parsing, fallback.

Behaviour contract used by every AI endpoint:
- Provider not configured → returns `None` (caller uses local rule-based data).
- Provider fails (network/auth/timeout/bad response) → logs safely, returns
  `None` (graceful fallback; the app keeps working offline).
- Rate limited → raises `AiRateLimited` (the router maps this to HTTP 429).
- Journal prompts pass through the safety wrapper first; prompt-injection
  attempts are refused without calling the provider.

A process-wide instance is exposed as `ai_service`; tests may construct their
own with an injected fake provider.
"""

from __future__ import annotations

from dataclasses import dataclass

from app.core.config import get_settings
from app.core.logging import get_logger
from app.schemas.ai import (
    InsightAggregates,
    InsightCard,
    ReflectionResponse,
)
from app.services.ai import prompts
from app.services.ai.openai_provider import OpenAiProvider
from app.services.ai.parser import (
    parse_insights,
    parse_reflection,
    parse_report_narrative,
)
from app.services.ai.provider import (
    AiProvider,
    AiProviderError,
    AiRateLimited,
)
from app.services.ai.safety import AiSafetyService

log = get_logger("moodly.ai")


@dataclass
class ReflectionOutcome:
    reflection: ReflectionResponse | None
    """None when AI is unavailable/failed → caller falls back to local rules."""
    safety_flagged: bool = False
    """True when output looked medical → caller shows a stronger disclaimer."""


class AiService:
    def __init__(
        self,
        provider: AiProvider | None = None,
        safety: AiSafetyService | None = None,
        auto_build_provider: bool = False,
    ) -> None:
        self._provider = provider
        self._safety = safety or AiSafetyService()
        self._auto_build = auto_build_provider

    @property
    def provider(self) -> AiProvider | None:
        if self._provider is None and self._auto_build:
            settings = get_settings()
            if settings.ai_enabled:
                self._provider = OpenAiProvider(
                    api_key=settings.openai_api_key or "",
                    model=settings.openai_model,
                    base_url=settings.openai_base_url,
                    timeout_seconds=settings.openai_timeout_seconds,
                )
        return self._provider

    @property
    def ai_enabled(self) -> bool:
        return self.provider is not None

    @property
    def provider_name(self) -> str:
        provider = self.provider
        return provider.name if provider else "none"

    # --- reflection -----------------------------------------------------------

    def generate_reflection(
        self,
        body: str,
        title: str | None,
        entry_date: str,
        mood: str | None,
    ) -> ReflectionOutcome:
        provider = self.provider
        if provider is None:
            return ReflectionOutcome(reflection=None)

        cleaned = self._safety.prepare_journal_text(body, title)
        if self._safety.contains_injection_attempt(body):
            # Refuse to run the prompt; caller falls back to local rules.
            log.info("reflection refused: prompt-injection heuristic matched")
            return ReflectionOutcome(reflection=None)

        system = prompts.REFLECTION_SYSTEM
        user = prompts.reflection_prompt(cleaned, title, entry_date, mood)
        try:
            raw = provider.chat_json(system, user)
        except AiRateLimited:
            raise
        except AiProviderError as exc:
            log.warning("reflection provider failed: %s", exc)
            return ReflectionOutcome(reflection=None)

        try:
            reflection = parse_reflection(raw, source=f"ai:{provider.name}")
        except AiProviderError as exc:
            log.warning("reflection parse failed: %s", exc)
            return ReflectionOutcome(reflection=None)

        check = self._safety.inspect_output_list(
            [reflection.summary, *reflection.positive_observations, *reflection.challenges]
        )
        return ReflectionOutcome(reflection=reflection, safety_flagged=check.flagged_medical)

    # --- insights -------------------------------------------------------------

    def generate_insights(
        self, aggregates: InsightAggregates
    ) -> list[InsightCard] | None:
        provider = self.provider
        if provider is None:
            return None
        try:
            raw = provider.chat_json(
                prompts.INSIGHT_SYSTEM, prompts.insight_prompt(aggregates)
            )
        except AiRateLimited:
            raise
        except AiProviderError as exc:
            log.warning("insights provider failed: %s", exc)
            return None
        try:
            return parse_insights(raw, source=f"ai:{provider.name}")
        except AiProviderError as exc:
            log.warning("insights parse failed: %s", exc)
            return None

    # --- report narrative -----------------------------------------------------

    def generate_report_narrative(
        self,
        aggregates: InsightAggregates,
        comparison: str | None,
        span_days: int,
    ) -> tuple[str, list[str]] | None:
        provider = self.provider
        if provider is None:
            return None
        try:
            raw = provider.chat_json(
                prompts.REPORT_SYSTEM,
                prompts.report_prompt(aggregates, comparison, span_days),
            )
        except AiRateLimited:
            raise
        except AiProviderError as exc:
            log.warning("report provider failed: %s", exc)
            return None
        try:
            return parse_report_narrative(raw, source=f"ai:{provider.name}")
        except AiProviderError as exc:
            log.warning("report parse failed: %s", exc)
            return None


# Process-wide instance (lazy provider from settings).
ai_service = AiService(auto_build_provider=True)
