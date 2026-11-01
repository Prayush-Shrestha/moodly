"""Health + AI provider status (public)."""

from fastapi import APIRouter

from app.core.config import get_settings
from app.schemas.ai import AiStatusResponse

router = APIRouter(tags=["health"])


@router.get("/health", summary="Service and database reachability")
def health() -> dict[str, str]:
    return {"status": "ok"}


@router.get(
    "/ai/status",
    response_model=AiStatusResponse,
    summary="Which AI mode the backend is running",
    description=(
        "`local_rules` means no provider key is configured — clients should "
        "use their on-device rule-based fallback. Never pretends AI is active."
    ),
)
def ai_status() -> AiStatusResponse:
    settings = get_settings()
    if settings.ai_enabled:
        return AiStatusResponse(
            ai_enabled=True, provider="openai", mode="remote_ai"
        )
    return AiStatusResponse(ai_enabled=False, provider="none", mode="local_rules")
