"""Provider abstraction for AI features.

`AiProvider` is the minimal interface every concrete provider implements.
Moodly never pretends AI ran: when no provider is configured, callers receive
`None` and fall back to the deterministic local rule-based logic.
"""

from __future__ import annotations

import abc


class AiProviderError(Exception):
    """Any provider-level failure (network, auth, rate limit, timeout)."""


class AiResponseError(AiProviderError):
    """The provider answered but with an unusable response."""


class AiRateLimited(AiProviderError):
    """Provider signalled a rate limit (HTTP 429)."""


class AiProvider(abc.ABC):
    """Describes the name/label of the implementation (for audit + UI)."""

    @property
    @abc.abstractmethod
    def name(self) -> str:
        """Human readable identifier, e.g. `openai:gpt-4o-mini`."""

    @abc.abstractmethod
    def chat_json(self, system_prompt: str, user_prompt: str) -> dict[str, object]:
        """Run a chat completion and return the parsed JSON object.

        Raises:
            AiRateLimited: provider throttled us.
            AiResponseError: response missing/malformed.
            AiProviderError: network/auth/timeout problems.
        """
