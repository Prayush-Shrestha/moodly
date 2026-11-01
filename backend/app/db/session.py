"""SQLAlchemy declarative base and engine/session wiring.

The engine is created from `Settings.database_url`:
- a SQLite URL works out of the box (local development and CI tests),
- a PostgreSQL URL (`DATABASE_URL=postgresql+psycopg2://...`) is the
  documented production target.

Tests call `set_engine()` with a disposable database before the first request;
`get_session()` (used by the FastAPI `get_db` dependency) reads the currently
bound sessionmaker, so overrides take effect app-wide.
"""

from __future__ import annotations

from typing import Any

from sqlalchemy import Engine, create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.core.config import get_settings


class Base(DeclarativeBase):
    """Common declarative base for every Moodly ORM model."""


def _sqlite_kwargs(url: str) -> dict[str, Any]:
    kwargs: dict[str, Any] = {"connect_args": {"check_same_thread": False}}
    if ":memory:" in url or "mode=memory" in url:
        from sqlalchemy.pool import StaticPool

        kwargs["poolclass"] = StaticPool
    return kwargs


def _default_engine() -> Engine:
    url = get_settings().database_url
    return create_engine(
        url, future=True, **(_sqlite_kwargs(url) if url.startswith("sqlite") else {})
    )


engine: Engine = _default_engine()
SessionFactory: sessionmaker[Session] = sessionmaker(bind=engine, expire_on_commit=False)


def set_engine(new_engine: Engine) -> None:
    """Swap the global engine (tests). Rebinds the session factory too."""
    global engine
    engine = new_engine
    SessionFactory.configure(bind=new_engine)


def get_session() -> Session:
    return SessionFactory()


def create_all() -> None:
    """Create every table on the bound engine (tests; production uses Alembic)."""
    import app.db.base  # noqa: F401  — model registration side effect

    Base.metadata.create_all(bind=engine)
    Base.metadata.reflect(bind=engine)


def drop_all() -> None:
    import app.db.base  # noqa: F401

    Base.metadata.drop_all(bind=engine)
