from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING, Any

from sqlalchemy import (
    CheckConstraint,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.models.enums import (
    ANSWER_STATUS_CHECK_SQL,
    ATTEMPT_STATUS_CHECK_SQL,
    AnswerStatus,
    AttemptStatus,
)
from app.models.types import JSONColumn, UTCDateTime, utcnow

if TYPE_CHECKING:
    from app.models.exam import Exam, ExamQuestion
    from app.models.user import User


class ExamAttempt(Base):
    """One sitting of an exam by one student.

    ``started_at`` and ``expires_at`` are written once, by the server, and never accepted
    from a client. Every timing decision afterwards is made by comparing the server clock
    to ``expires_at``, so changing the device clock or patching the app changes nothing
    (docs/security.md §3).
    """

    __tablename__ = "exam_attempts"
    __table_args__ = (
        CheckConstraint(ATTEMPT_STATUS_CHECK_SQL, name="status"),
        # A student may only have one attempt running at a time. Finished attempts are
        # unconstrained, so a second sitting is possible where the exam allows it.
        Index(
            "uq_exam_attempts_active",
            "exam_id",
            "student_id",
            unique=True,
            postgresql_where=text("status = 'active'"),
            sqlite_where=text("status = 'active'"),
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    exam_id: Mapped[int] = mapped_column(
        ForeignKey("exams.id", ondelete="CASCADE"), nullable=False, index=True
    )
    student_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    started_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utcnow, server_default=func.now()
    )
    expires_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False)
    submitted_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default=AttemptStatus.ACTIVE.value, index=True
    )

    # This student's personal order, fixed once at creation (§35). Regenerating it per
    # request would reshuffle the paper under the student mid-exam.
    question_order: Mapped[list[int]] = mapped_column(JSONColumn, nullable=False)

    # {exam_question_id: [option_id, ...]} in this student's order (§36). Option *ids*,
    # never letters — the letter a student saw is meaningless when grading.
    option_orders: Mapped[dict[str, list[int]]] = mapped_column(JSONColumn, nullable=False)

    exam: Mapped["Exam"] = relationship()
    student: Mapped["User"] = relationship()
    answers: Mapped[list["StudentAnswer"]] = relationship(
        back_populates="attempt", cascade="all, delete-orphan"
    )

    @property
    def is_active(self) -> bool:
        return self.status == AttemptStatus.ACTIVE

    def remaining_seconds(self, now: datetime) -> int:
        """Never negative, and never derived from anything the client sent."""
        if not self.is_active:
            return 0
        return max(0, int((self.expires_at - now).total_seconds()))

    def has_expired(self, now: datetime) -> bool:
        return now >= self.expires_at

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return f"<ExamAttempt {self.id} exam={self.exam_id} {self.status}>"


class StudentAnswer(Base):
    """One answer within an attempt.

    Keyed by ``exam_question_id`` rather than ``question_id``: what identifies a question
    inside a published exam is its link row, which carries the frozen snapshot that
    grading scores against.
    """

    __tablename__ = "student_answers"
    __table_args__ = (
        UniqueConstraint(
            "attempt_id", "exam_question_id", name="uq_student_answers_attempt_question"
        ),
        CheckConstraint(ANSWER_STATUS_CHECK_SQL, name="status"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    attempt_id: Mapped[int] = mapped_column(
        ForeignKey("exam_attempts.id", ondelete="CASCADE"), nullable=False, index=True
    )
    exam_question_id: Mapped[int] = mapped_column(
        ForeignKey("exam_questions.id", ondelete="CASCADE"), nullable=False, index=True
    )

    # MCQ answers are an option id; the free-text columns are for the later phases.
    selected_option_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    answer_text: Mapped[str | None] = mapped_column(Text, nullable=True)

    marks_awarded: Mapped[float | None] = mapped_column(Numeric(6, 2), nullable=True)
    feedback: Mapped[str | None] = mapped_column(Text, nullable=True)
    evaluated_by: Mapped[int | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    evaluated_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default=AnswerStatus.PENDING.value
    )
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime,
        nullable=False,
        default=utcnow,
        onupdate=utcnow,
        server_default=func.now(),
    )

    attempt: Mapped["ExamAttempt"] = relationship(back_populates="answers")
    exam_question: Mapped["ExamQuestion"] = relationship()

    @property
    def is_answered(self) -> bool:
        return self.selected_option_id is not None or bool(self.answer_text)
