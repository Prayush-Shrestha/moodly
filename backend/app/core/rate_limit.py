"""In-process rate limiting.

A sliding-window limiter keyed by (bucket, client key) using only the
standard library — no Redis/external dependency. Suitable for a single
instance; for multi-instance deployments use a shared store (documented as a
future improvement).

Bucket configuration is per scope ("auth", "ai"), configurable via env.
"""

from __future__ import annotations

import threading
import time
from collections import deque
from dataclasses import dataclass, field

from fastapi import HTTPException, Request, status

from app.core.config import get_settings


@dataclass
class _Bucket:
    events: deque[float] = field(default_factory=deque)


class RateLimiter:
    def __init__(self) -> None:
        self._buckets: dict[str, _Bucket] = {}
        self._lock = threading.Lock()

    def hit(self, key: str, limit: int, window_seconds: float = 60.0) -> None:
        """Record one event for `key`, raising 429 when over `limit`/window."""
        if limit <= 0:
            return
        now = time.monotonic()
        with self._lock:
            bucket = self._buckets.setdefault(key, _Bucket())
            events = bucket.events
            while events and now - events[0] > window_seconds:
                events.popleft()
            if len(events) >= limit:
                # Retry-After: seconds until the oldest event leaves the window.
                retry_after = max(1, int(window_seconds - (now - events[0])) + 1)
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail="Too many requests. Please try again later.",
                    headers={"Retry-After": str(retry_after)},
                )
            events.append(now)

    def reset(self) -> None:
        with self._lock:
            self._buckets.clear()


_limiter = RateLimiter()


def client_key(request: Request) -> str:
    """Best-effort client identity for an in-process limiter."""
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    host = request.client.host if request.client else "unknown"
    return host


def limit_auth(request: Request) -> None:
    settings = get_settings()
    if not settings.rate_limit_enabled:
        return
    _limiter.hit(f"auth:{client_key(request)}", settings.auth_requests_per_minute)


def limit_ai(
    request: Request, user_id: int | None = None
) -> None:
    """AI calls are limited per account when signed in, else per client IP."""
    settings = get_settings()
    if not settings.rate_limit_enabled:
        return
    if user_id is not None:
        _limiter.hit(f"ai-user:{user_id}", settings.ai_requests_per_minute)
    else:
        _limiter.hit(f"ai-ip:{client_key(request)}", settings.ai_requests_per_minute)


def reset_rate_limiter() -> None:
    """Exposed for tests only."""
    _limiter.reset()
