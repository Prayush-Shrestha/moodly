"""OpenAI-compatible chat-completions provider.

Uses `httpx` with a hard timeout and bounded retries with exponential backoff
for transient failures (429/5xx/network). The API key is read ONLY from
backend environment variables — it never reaches Flutter or source control.

Works against the public OpenAI API or any self-hosted/proxy that speaks the
`/chat/completions` protocol (set OPENAI_BASE_URL).
"""

from __future__ import annotations

import json
import time

import httpx

from app.core.config import get_settings
from app.core.logging import get_logger
from app.services.ai.parser import parse_json_object
from app.services.ai.provider import (
    AiProvider,
    AiProviderError,
    AiRateLimited,
    AiResponseError,
)

log = get_logger("moodly.ai.openai")

_MAX_RETRIES = 3
_RETRY_BACKOFF_SECONDS = (0.5, 1.5)  # after 1st and 2nd retry


class OpenAiProvider(AiProvider):
    def __init__(
        self,
        api_key: str,
        model: str,
        base_url: str,
        timeout_seconds: int = 30,
    ) -> None:
        self._api_key = api_key
        self._model = model
        self._base_url = base_url.rstrip("/")
        self._timeout = timeout_seconds

    @property
    def name(self) -> str:
        return f"openai:{self._model}"

    def chat_json(self, system_prompt: str, user_prompt: str) -> dict[str, object]:
        payload = {
            "model": self._model,
            "temperature": 0.4,
            "response_format": {"type": "json_object"},
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
        }
        headers = {
            "Authorization": f"Bearer {self._api_key}",
            "Content-Type": "application/json",
        }
        url = f"{self._base_url}/chat/completions"

        last_error: Exception | None = None
        for attempt in range(_MAX_RETRIES + 1):
            try:
                response = httpx.post(
                    url, json=payload, headers=headers, timeout=self._timeout
                )
            except httpx.TimeoutException as exc:
                last_error = AiProviderError("AI request timed out")
                log.warning("openai timeout (attempt %s)", attempt)
            except httpx.HTTPError as exc:
                last_error = AiProviderError("AI network error")
                log.warning("openai network error (attempt %s)", attempt)
            else:
                if response.status_code == 429:
                    last_error = AiRateLimited("AI provider rate limit reached")
                    # Respect Retry-After when provided.
                    retry_after = response.headers.get("retry-after")
                    self._sleep_before_retry(attempt, retry_after)
                    continue
                if response.status_code in (500, 502, 503, 504):
                    last_error = AiProviderError("AI provider unavailable")
                    self._sleep_before_retry(attempt, None)
                    continue
                if response.status_code in (401, 403):
                    # Do NOT log the body (may echo parts of the key/headers).
                    raise AiProviderError("AI provider rejected the credentials")
                if response.status_code >= 400:
                    raise AiProviderError(f"AI provider error (HTTP {response.status_code})")
                return self._parse_completion(response)
            if attempt < _MAX_RETRIES:
                self._sleep_before_retry(attempt, None)

        raise last_error or AiProviderError("AI provider failed")

    @staticmethod
    def _sleep_before_retry(attempt: int, retry_after: str | None) -> None:
        delay = None
        if retry_after:
            try:
                delay = max(0.0, min(float(retry_after), 10.0))
            except ValueError:
                delay = None
        if delay is None:
            delay = _RETRY_BACKOFF_SECONDS[min(attempt, len(_RETRY_BACKOFF_SECONDS) - 1)]
        time.sleep(delay)

    @staticmethod
    def _parse_completion(response: httpx.Response) -> dict[str, object]:
        try:
            data = response.json()
        except (json.JSONDecodeError, ValueError) as exc:
            raise AiResponseError("AI provider returned non-JSON") from exc
        try:
            content = data["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError) as exc:
            raise AiResponseError("AI provider response missing content") from exc
        if not isinstance(content, str) or not content.strip():
            raise AiResponseError("AI provider returned empty content")
        return parse_json_object(content)
