from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING, Any

from sqlalchemy import CheckConstraint, ForeignKey, Index, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.models.enums import (
    SECURITY_EVENT_CHECK_SQL,
    SECURITY_SEVERITY_CHECK_SQL,
    SecuritySeverity,
)
from app.models.types import JSONColumn, UTCDateTime, utcnow

if TYPE_CHECKING:
    from app.models.attempt import ExamAttempt
    from app.models.user import User


class SecurityEvent(Base):
    """Something the device reported during an exam (§39).

    This is an evidence trail for a human invigilator, not a verdict. The platform never
    terminates an attempt or flags a student on the strength of these rows: a backgrounded
    app may be an incoming call, and a dropped network may be a bad signal. Recording what
    happened, with a server timestamp, is the useful part (docs/security.md §9).
    """

    __tablename__ = "security_events"
    __table_args__ = (
        CheckConstraint(SECURITY_EVENT_CHECK_SQL, name="event_type"),
        CheckConstraint(SECURITY_SEVERITY_CHECK_SQL, name="severity"),
        Index("ix_security_events_attempt_time", "attempt_id", "occurred_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    attempt_id: Mapped[int] = mapped_column(
        ForeignKey("exam_attempts.id", ondelete="CASCADE"), nullable=False, index=True
    )
    student_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    event_type: Mapped[str] = mapped_column(String(40), nullable=False, index=True)

    # The server's clock, not the device's. A device that reports a time is reporting a
    # claim; this column records when the report actually arrived.
    occurred_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utcnow, server_default=func.now()
    )
    severity: Mapped[str] = mapped_column(
        String(20), nullable=False, default=SecuritySeverity.INFO.value
    )
    event_metadata: Mapped[dict[str, Any] | None] = mapped_column(
        "metadata", JSONColumn, nullable=True
    )

    attempt: Mapped["ExamAttempt"] = relationship()
    student: Mapped["User"] = relationship()

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return f"<SecurityEvent {self.event_type} attempt={self.attempt_id}>"
