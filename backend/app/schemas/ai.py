"""AI request/response schemas.

Important privacy property: insight and report narrative requests carry only
AGGREGATE statistics — never journal text. Reflection requests carry one
journal entry and require the caller to assert consent.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field

MoodDist = dict[str, int]


class ReflectionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    journal_body: str = Field(min_length=1, max_length=20000)
    journal_title: str | None = Field(default=None, max_length=200)
    entry_date: str = Field(pattern=r"^\d{4}-\d{2}-\d{2}$")
    mood: str | None = Field(default=None, max_length=16)
    # The client must have shown the AI-processing consent screen. Mirroring
    # the flag here lets the backend audit intent; the UI gates this too.
    consent_given: bool = Field(default=False)


class ReflectionResponse(BaseModel):
    summary: str
    explicit_emotions: list[str]
    inferred_emotions: list[str] = []
    themes: list[str]
    positive_observations: list[str]
    challenges: list[str]
    reflection_questions: list[str]
    source: str  # "ai:<provider/model>" or "local_rules"
    disclaimer_shown: bool = True


class InsightAggregates(BaseModel):
    model_config = ConfigDict(extra="forbid")

    analysis_from: str = Field(pattern=r"^\d{4}-\d{2}-\d{2}$")
    analysis_to: str = Field(pattern=r"^\d{4}-\d{2}-\d{2}$")
    period_label: str = Field(max_length=40)
    total_checkins: int = Field(ge=0, le=100000)
    mood_distribution: MoodDist
    dominant_mood: str | None = Field(default=None, max_length=16)
    average_energy: float | None = Field(default=None, ge=0, le=5)
    top_emotions: list[str] = Field(default_factory=list, max_length=10)
    consistent_days: int = Field(ge=0, le=100000)
    streak_days: int = Field(ge=0, le=100000)
    locale: str = Field(default="en", max_length=10)


class InsightCard(BaseModel):
    title: str
    body: str
    icon: str | None = None
    data_basis: str


class InsightResponse(BaseModel):
    insights: list[InsightCard]
    source: str


class ReportNarrativeRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    period_label: str = Field(max_length=40)
    aggregates: InsightAggregates
    comparison_available: bool = False
    comparison_summary: str | None = Field(default=None, max_length=2000)


class ReportNarrativeResponse(BaseModel):
    narrative: str
    reflection_questions: list[str] = Field(default_factory=list, max_length=6)
    source: str


class AiStatusResponse(BaseModel):
    ai_enabled: bool
    provider: str
    mode: str  # "remote_ai" or "local_rules"
