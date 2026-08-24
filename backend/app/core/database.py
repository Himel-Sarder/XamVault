"""Engine, session factory and the declarative base.

The engine is configured differently for PostgreSQL and SQLite: Render's managed Postgres
closes idle connections (hence ``pool_pre_ping`` / ``pool_recycle``), while the SQLite URL
used by the test suite does not accept pool sizing arguments at all.
"""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

from sqlalchemy import MetaData, create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.core.config import settings

# Deterministic constraint names. Without these, Alembic autogenerate cannot emit a
# working downgrade for unnamed constraints, and SQLite batch migrations fail outright.
NAMING_CONVENTION = {
    "ix": "ix_%(table_name)s_%(column_0_N_name)s",
    "uq": "uq_%(table_name)s_%(column_0_N_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_N_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=NAMING_CONVENTION)


def _engine_kwargs(url: str) -> dict[str, Any]:
    if url.startswith("sqlite"):
        kwargs: dict[str, Any] = {"connect_args": {"check_same_thread": False}}
        if ":memory:" in url:
            # One shared in-memory database for the whole process, otherwise each
            # connection would see its own empty schema.
            from sqlalchemy.pool import StaticPool

            kwargs["poolclass"] = StaticPool
        return kwargs
    return {
        "pool_size": settings.DB_POOL_SIZE,
        "max_overflow": settings.DB_MAX_OVERFLOW,
        "pool_recycle": settings.DB_POOL_RECYCLE_SECONDS,
        "pool_pre_ping": True,
    }


engine = create_engine(
    settings.DATABASE_URL,
    echo=settings.DB_ECHO,
    future=True,
    **_engine_kwargs(settings.DATABASE_URL),
)

SessionLocal = sessionmaker(
    bind=engine,
    autoflush=False,
    autocommit=False,
    expire_on_commit=False,
    class_=Session,
)


def get_db() -> Iterator[Session]:
    """FastAPI dependency: one session per request, always closed.

    Services own their commit boundaries; this only guarantees rollback on an
    unhandled error so a failed request never leaves a half-applied transaction.
    """
    db = SessionLocal()
    try:
        yield db
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()
