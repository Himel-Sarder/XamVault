from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import CheckConstraint, ForeignKey, Numeric, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.models.enums import RESULT_STATUS_CHECK_SQL, ResultStatus
from app.models.types import UTCDateTime, utcnow

if TYPE_CHECKING:
    from app.models.attempt import ExamAttempt
    from app.models.exam import Exam
    from app.models.user import User


class Result(Base):
    """The score for one attempt.

    Split by question kind because the three are graded by different mechanisms and at
    different times: MCQ automatically at submission, short answers by the teacher, code
    by the sandbox worker. ``total_score`` is their sum, never a client-supplied number.
    """

    __tablename__ = "results"
    __table_args__ = (CheckConstraint(RESULT_STATUS_CHECK_SQL, name="status"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    exam_id: Mapped[int] = mapped_column(
        ForeignKey("exams.id", ondelete="CASCADE"), nullable=False, index=True
    )
    student_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    # One result per attempt: the uniqueness is what makes submission idempotent.
    attempt_id: Mapped[int] = mapped_column(
        ForeignKey("exam_attempts.id", ondelete="CASCADE"), unique=True, nullable=False
    )

    mcq_score: Mapped[float] = mapped_column(Numeric(7, 2), nullable=False, default=0)
    short_answer_score: Mapped[float] = mapped_column(Numeric(7, 2), nullable=False, default=0)
    code_score: Mapped[float] = mapped_column(Numeric(7, 2), nullable=False, default=0)
    total_score: Mapped[float] = mapped_column(Numeric(7, 2), nullable=False, default=0)
    percentage: Mapped[float] = mapped_column(Numeric(5, 2), nullable=False, default=0)

    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default=ResultStatus.PENDING.value, index=True
    )
    published_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utcnow, server_default=func.now()
    )

    exam: Mapped["Exam"] = relationship()
    student: Mapped["User"] = relationship()
    attempt: Mapped["ExamAttempt"] = relationship()

    @property
    def is_published(self) -> bool:
        return self.status == ResultStatus.PUBLISHED

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return f"<Result attempt={self.attempt_id} total={self.total_score}>"
