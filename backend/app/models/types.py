"""Custom column types shared by the models."""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import DateTime, JSON
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.types import TypeDecorator


class UTCDateTime(TypeDecorator):
    """A timestamp that is always stored and returned as timezone-aware UTC.

    PostgreSQL ``TIMESTAMPTZ`` already round-trips an offset, but SQLite (used by the
    test suite) silently drops ``tzinfo``. Without this decorator the same expression —
    ``attempt.expires_at < datetime.now(UTC)`` — would work against Postgres and raise
    ``TypeError: can't compare offset-naive and offset-aware datetimes`` in tests.
    """

    impl = DateTime(timezone=True)
    cache_ok = True

    def process_bind_param(self, value: datetime | None, dialect) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            value = value.replace(tzinfo=UTC)
        return value.astimezone(UTC)

    def process_result_value(self, value: datetime | None, dialect) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            return value.replace(tzinfo=UTC)
        return value.astimezone(UTC)


def utcnow() -> datetime:
    return datetime.now(UTC)


# JSONB on PostgreSQL (indexable, binary-stored), plain JSON on SQLite so the test suite
# runs on the same models.
JSONColumn = JSON().with_variant(JSONB, "postgresql")
