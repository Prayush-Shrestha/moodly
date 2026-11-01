"""AI endpoints.

All AI endpoints require an authenticated account (documented in the app) and
are rate limited per user. Privacy guarantees:

- `/ai/reflection` receives exactly one journal entry, only after the client
  confirms the user's AI-processing consent; bodies are never logged.
- `/ai/insights` and `/ai/report-narrative` receive only AGGREGATE statistics.

Graceful degradation: when no provider is configured (or it fails), endpoints
still return useful local rule-based results with `source: "local_rules"`, so
the app never pretends AI is active.
"""

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from app.core.deps import get_db, require_current_user
from app.core.rate_limit import limit_ai
from app.db.base import User
from app.schemas.ai import (
    InsightAggregates,
    InsightCard,
    InsightResponse,
    ReflectionRequest,
    ReflectionResponse,
    ReportNarrativeRequest,
    ReportNarrativeResponse,
)
from app.services.ai.local_rules import local_insight_cards, local_report_narrative
from app.services.ai.provider import AiRateLimited
from app.services.ai.service import ai_service

router = APIRouter(prefix="/ai", tags=["ai"])


@router.post(
    "/reflection",
    response_model=ReflectionResponse,
    summary="AI reflection for one journal entry (consent required)",
    description=(
        "Generates a structured reflection: short summary, explicitly expressed "
        "emotions (kept separate from inferred ones), themes, positive "
        "observations, challenges, and exactly 3 reflection questions. "
        "Requires `consent_given=true` — the app must have shown the "
        "AI-processing consent screen first. Returns local rule-based results "
        "when no AI provider is configured."
    ),
)
def reflection(
    payload: ReflectionRequest,
    request: Request,
    user: User = Depends(require_current_user),
    db: Session = Depends(get_db),
) -> ReflectionResponse:
    limit_ai(request, user_id=user.id)
    if not payload.consent_given:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="AI processing consent is required before journal text is processed",
        )

    if ai_service.ai_enabled:
        try:
            outcome = ai_service.generate_reflection(
                body=payload.journal_body,
                title=payload.journal_title,
                entry_date=payload.entry_date,
                mood=payload.mood,
            )
        except AiRateLimited as exc:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=str(exc),
                headers={"Retry-After": "60"},
            )
        if outcome.reflection is not None:
            return outcome.reflection

    # Local rule-based fallback (mirrors the on-device implementation).
    from app.services.ai.local_reflection import local_reflection

    result = local_reflection(
        body=payload.journal_body,
        title=payload.journal_title,
        entry_date=payload.entry_date,
        mood=payload.mood,
    )
    return result


@router.post(
    "/insights",
    response_model=InsightResponse,
    summary="Personalized insight cards from aggregate statistics",
    description=(
        "Receives only aggregate statistics (never journal text) and returns "
        "2–6 insight cards. Each card includes `data_basis` explaining which "
        "numbers support it."
    ),
)
def insights(
    payload: InsightAggregates,
    request: Request,
    user: User = Depends(require_current_user),
) -> InsightResponse:
    limit_ai(request, user_id=user.id)
    if payload.total_checkins == 0:
        return InsightResponse(
            insights=local_insight_cards(payload), source="local_rules"
        )
    if ai_service.ai_enabled:
        try:
            cards = ai_service.generate_insights(payload)
        except AiRateLimited as exc:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=str(exc),
                headers={"Retry-After": "60"},
            )
        if cards:
            return InsightResponse(insights=cards, source=f"ai:{ai_service.provider_name}")
    return InsightResponse(insights=local_insight_cards(payload), source="local_rules")


@router.post(
    "/report-narrative",
    response_model=ReportNarrativeResponse,
    summary="AI report narrative + reflection questions from aggregates",
)
def report_narrative(
    payload: ReportNarrativeRequest,
    request: Request,
    user: User = Depends(require_current_user),
) -> ReportNarrativeResponse:
    limit_ai(request, user_id=user.id)
    from datetime import date

    try:
        start = date.fromisoformat(payload.aggregates.analysis_from)
        end = date.fromisoformat(payload.aggregates.analysis_to)
        span_days = max(1, (end - start).days + 1)
    except ValueError:
        span_days = 1

    if ai_service.ai_enabled:
        try:
            generated = ai_service.generate_report_narrative(
                payload.aggregates, payload.comparison_summary, span_days
            )
        except AiRateLimited as exc:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=str(exc),
                headers={"Retry-After": "60"},
            )
        if generated is not None:
            narrative, questions = generated
            return ReportNarrativeResponse(
                narrative=narrative,
                reflection_questions=questions,
                source=f"ai:{ai_service.provider_name}",
            )

    narrative, questions = local_report_narrative(
        payload.aggregates, payload.comparison_summary
    )
    return ReportNarrativeResponse(
        narrative=narrative, reflection_questions=questions, source="local_rules"
    )
