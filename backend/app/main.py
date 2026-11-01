"""FastAPI application factory.

- Global exception handlers that never leak internals or user content.
- Structured, safe logging (request bodies are never logged).
- CORS from environment configuration.
- OpenAPI docs at /docs (Swagger UI) and /redoc.
"""

from __future__ import annotations

from contextlib import asynccontextmanager
from collections.abc import AsyncIterator

from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

import app.db.base  # noqa: F401 — model registration
from app.core.config import get_settings
from app.core.logging import get_logger, setup_logging
from app.routers import ai as ai_router
from app.routers import auth as auth_router
from app.routers import health as health_router
from app.routers import sync as sync_router
from app.routers import users as users_router

log = get_logger("moodly.app")

DESCRIPTION = """\
Moodly's backend provides optional accounts, cloud synchronization and
AI-powered reflection for the Moodly Flutter app.

**Privacy:**
- Journal text is accepted only on `/ai/reflection` after explicit consent.
- `/ai/insights` and `/ai/report-narrative` accept only aggregate statistics.
- Without an AI provider key configured, AI endpoints return local
  rule-based results (source: `local_rules`) — the app keeps working.

**Auth:** Bearer access token (30 min) + rotating refresh token (30 days).
"""


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings = get_settings()
    setup_logging(settings.log_level)
    log.info(
        "starting moodly backend (ai_enabled=%s, dev_mode=%s)",
        settings.ai_enabled,
        settings.dev_mode,
    )
    yield
    log.info("shutting down")


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title="Moodly API",
        version="3.0.0",
        description=DESCRIPTION,
        lifespan=lifespan,
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origin_list or [],
        allow_credentials=False,
        allow_methods=["GET", "POST", "PATCH", "DELETE"],
        allow_headers=["Authorization", "Content-Type"],
    )

    # --- error handlers -----------------------------------------------------
    @app.exception_handler(RequestValidationError)
    async def validation_handler(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        # Return field names + messages only; never echo raw values (they may
        # contain journal text).
        errors = [
            {"field": ".".join(str(loc) for loc in err.get("loc", ())), "message": err.get("msg", "invalid")}
            for err in exc.errors()[:10]
        ]
        return JSONResponse(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            content={"detail": "Validation failed", "errors": errors},
        )

    @app.exception_handler(Exception)
    async def generic_handler(request: Request, exc: Exception) -> JSONResponse:
        # Log without the body; respond generically.
        log.error("unhandled error on %s: %s", request.url.path, type(exc).__name__)
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content={"detail": "Internal server error"},
        )

    # --- routers -------------------------------------------------------------
    app.include_router(health_router.router)
    app.include_router(auth_router.router)
    app.include_router(users_router.router)
    app.include_router(sync_router.router)
    app.include_router(ai_router.router)

    return app


app = create_app()
