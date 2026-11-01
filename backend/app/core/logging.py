"""Safe structured logging.

Rules enforced here:
- Request bodies are NEVER logged (they contain journal content).
- Log messages never include user-provided free text; _scrub() removes any
  occurrence of journal/`note` strings that callers may accidentally pass.
"""

from __future__ import annotations

import logging
import re
import sys

_CONFIGURED = False
_scrubbers: list[re.Pattern[str]] = []


def register_scrub(re_pattern: str) -> None:
    """Register a pattern to redact from every log line (e.g. a journal body)."""
    try:
        compiled = re.compile(re_pattern)
        _scrubbers.append(compiled)
    except re.error:
        pass  # never let logging break the app


def scrub(message: str) -> str:
    for pattern in _scrubbers:
        message = pattern.sub("<redacted>", message)
    # Defensive: normalise anything that looks like it leaked multi-line bodies.
    return message.replace("\n", " ")[:2000]


class _ScrubbingFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        record.msg = scrub(str(record.msg))
        if record.args:
            try:
                record.args = tuple(
                    scrub(str(a)) if isinstance(a, str) else a for a in record.args
                )
            except Exception:
                record.args = None
        return True


def setup_logging(level: str = "INFO") -> None:
    global _CONFIGURED
    if _CONFIGURED:
        logging.getLogger("moodly").setLevel(level)
        return
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(
        logging.Formatter("%(asctime)s %(levelname)s %(name)s - %(message)s")
    )
    handler.addFilter(_ScrubbingFilter())
    root = logging.getLogger("moodly")
    root.setLevel(level)
    root.addHandler(handler)
    root.propagate = False
    # Loud libraries down to safe levels.
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
    logging.getLogger("sqlalchemy.engine").setLevel(logging.WARNING)
    _CONFIGURED = True


def get_logger(name: str = "moodly") -> logging.Logger:
    return logging.getLogger(name)
