from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import CheckConstraint, ForeignKey, Index, String, func, text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.models.enums import JOIN_REQUEST_STATUS_CHECK_SQL, JoinRequestStatus
from app.models.types import UTCDateTime, utcnow

if TYPE_CHECKING:
    from app.models.exam import Exam
    from app.models.user import User


class JoinRequest(Base):
    """A student asking to sit an exam, and the teacher's decision.

    Enrolment says a student belongs to the course; this says the teacher has admitted
    them to *this* exam sitting. Phase 9 refuses to start an attempt without an approved
    request.
    """

    __tablename__ = "join_requests"
    __table_args__ = (
        CheckConstraint(JOIN_REQUEST_STATUS_CHECK_SQL, name="status"),
        # A student may ask again after a rejection, but may not have two requests
        # pending at once. A plain UNIQUE(exam_id, student_id) would forbid the retry,
        # so the constraint is partial - and it is the database, not the service, that
        # makes a duplicate impossible under concurrent requests.
        Index(
            "uq_join_requests_pending",
            "exam_id",
            "student_id",
            unique=True,
            postgresql_where=text("status = 'pending'"),
            sqlite_where=text("status = 'pending'"),
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    exam_id: Mapped[int] = mapped_column(
        ForeignKey("exams.id", ondelete="CASCADE"), nullable=False, index=True
    )
    student_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default=JoinRequestStatus.PENDING.value, index=True
    )
    requested_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utcnow, server_default=func.now()
    )
    reviewed_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)
    reviewed_by: Mapped[int | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )

    exam: Mapped["Exam"] = relationship()
    student: Mapped["User"] = relationship(foreign_keys=[student_id])
    reviewer: Mapped["User | None"] = relationship(foreign_keys=[reviewed_by])

    @property
    def is_pending(self) -> bool:
        return self.status == JoinRequestStatus.PENDING

    @property
    def is_approved(self) -> bool:
        return self.status == JoinRequestStatus.APPROVED

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return f"<JoinRequest exam={self.exam_id} student={self.student_id} {self.status}>"
