from __future__ import annotations

from datetime import datetime, timedelta
from typing import TYPE_CHECKING, Any

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    ForeignKey,
    Integer,
    String,
    Text,
    false as sa_false,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.models.enums import EXAM_STATUS_CHECK_SQL, ExamStatus
from app.models.types import JSONColumn, UTCDateTime, utcnow

if TYPE_CHECKING:
    from app.models.course import Course
    from app.models.question import Question
    from app.models.user import User


class Exam(Base):
    __tablename__ = "exams"
    __table_args__ = (
        CheckConstraint(EXAM_STATUS_CHECK_SQL, name="status"),
        CheckConstraint("duration_minutes > 0", name="duration_positive"),
        CheckConstraint("total_marks >= 0", name="total_marks_non_negative"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    course_id: Mapped[int] = mapped_column(
        ForeignKey("courses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    teacher_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    start_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)
    duration_minutes: Mapped[int] = mapped_column(Integer, nullable=False)

    # Derived at publish time from start_at + duration. Never accepted from a client:
    # it is the anchor the server-side timer will be computed against (docs/security.md §3).
    expires_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)

    # Always the sum of the attached questions' marks; never client-supplied.
    total_marks: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default=ExamStatus.DRAFT.value, index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utcnow, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime,
        nullable=False,
        default=utcnow,
        onupdate=utcnow,
        server_default=func.now(),
    )
    published_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)

    course: Mapped["Course"] = relationship()
    teacher: Mapped["User"] = relationship()
    settings: Mapped["ExamSettings"] = relationship(
        back_populates="exam", cascade="all, delete-orphan", uselist=False
    )
    questions: Mapped[list["ExamQuestion"]] = relationship(
        back_populates="exam",
        cascade="all, delete-orphan",
        order_by="ExamQuestion.display_order",
    )

    @property
    def is_draft(self) -> bool:
        return self.status == ExamStatus.DRAFT

    @property
    def is_published(self) -> bool:
        return self.status == ExamStatus.PUBLISHED

    @property
    def question_count(self) -> int:
        return len(self.questions)

    def duration_window(self) -> timedelta:
        return timedelta(minutes=self.duration_minutes)

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return f"<Exam {self.id} {self.title!r} ({self.status})>"


class ExamSettings(Base):
    """Per-exam configuration (§27). Created with the exam so it is never missing."""

    __tablename__ = "exam_settings"
    __table_args__ = (CheckConstraint("max_attempts >= 1", name="max_attempts_positive"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    exam_id: Mapped[int] = mapped_column(
        ForeignKey("exams.id", ondelete="CASCADE"), unique=True, nullable=False
    )
    shuffle_questions: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    shuffle_answers: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    allow_back_navigation: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    auto_submit: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    secure_mode: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    show_result_immediately: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False
    )
    max_attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=1)

    #: Whether an enrolled student may sit this exam without being admitted by hand.
    #:
    #: Manual approval is the default and stays the default: a teacher deciding who is
    #: in the room is the safer position, and turning that off should be a deliberate
    #: act. Auto-approval is for the ordinary case where everyone enrolled on the
    #: course is expected to sit the paper and the approval step is only friction.
    #:
    #: Enrolment is still required either way. This decides whether a *second* gate
    #: exists, not whether there is one.
    auto_approve_join: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=sa_false()
    )

    exam: Mapped["Exam"] = relationship(back_populates="settings")


class ExamQuestion(Base):
    """Links a question into an exam, and freezes it at publish time.

    ``question_snapshot`` is written when the exam is published. After that the exam
    renders from the snapshot, so editing the underlying question — or reusing it in
    another exam — cannot alter an exam students have already been shown (§17).
    """

    __tablename__ = "exam_questions"
    __table_args__ = (
        UniqueConstraint("exam_id", "question_id", name="uq_exam_questions_exam_question"),
        CheckConstraint("marks_snapshot > 0", name="marks_snapshot_positive"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    exam_id: Mapped[int] = mapped_column(
        ForeignKey("exams.id", ondelete="CASCADE"), nullable=False, index=True
    )
    question_id: Mapped[int] = mapped_column(
        ForeignKey("questions.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    question_snapshot: Mapped[dict[str, Any] | None] = mapped_column(
        JSONColumn, nullable=True
    )
    marks_snapshot: Mapped[int] = mapped_column(Integer, nullable=False)
    display_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    exam: Mapped["Exam"] = relationship(back_populates="questions")
    question: Mapped["Question"] = relationship(back_populates="exam_links")

    @property
    def is_frozen(self) -> bool:
        """True once the exam is published and this question is served from its
        immutable snapshot rather than the live question row."""
        return self.question_snapshot is not None
