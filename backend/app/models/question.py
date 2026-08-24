from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, CheckConstraint, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.models.enums import QUESTION_TYPE_CHECK_SQL
from app.models.types import UTCDateTime, utcnow

if TYPE_CHECKING:
    from app.models.exam import ExamQuestion
    from app.models.user import User


class Question(Base):
    """A reusable question.

    Lives independently of any exam so the same question can be reused (the Phase 6
    question bank). Attaching it to an exam happens through ``exam_questions``.
    """

    __tablename__ = "questions"
    __table_args__ = (
        CheckConstraint(QUESTION_TYPE_CHECK_SQL, name="type"),
        CheckConstraint("marks > 0", name="marks_positive"),
        CheckConstraint(
            "time_limit_seconds IS NULL OR time_limit_seconds > 0", name="time_limit_positive"
        ),
        CheckConstraint(
            "memory_limit_mb IS NULL OR memory_limit_mb > 0", name="memory_limit_positive"
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    type: Mapped[str] = mapped_column(String(30), nullable=False, index=True)
    question_text: Mapped[str] = mapped_column(Text, nullable=False)
    question_image_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    marks: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    difficulty: Mapped[str | None] = mapped_column(String(20), nullable=True)
    topic: Mapped[str | None] = mapped_column(String(150), nullable=True, index=True)
    created_by: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), nullable=False, index=True
    )

    # CODE_ANSWER configuration (§22). Nullable because only that type uses them; the
    # sandbox worker of Phase 15 will read the limits, and until it exists they are
    # shown to the student and recorded with the submission.
    language: Mapped[str | None] = mapped_column(String(30), nullable=True)
    time_limit_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)
    memory_limit_mb: Mapped[int | None] = mapped_column(Integer, nullable=True)
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

    options: Mapped[list["QuestionOption"]] = relationship(
        back_populates="question",
        cascade="all, delete-orphan",
        order_by="QuestionOption.display_order",
    )
    creator: Mapped["User"] = relationship()
    exam_links: Mapped[list["ExamQuestion"]] = relationship(back_populates="question")

    @property
    def correct_option_ids(self) -> list[int]:
        return [option.id for option in self.options if option.is_correct]

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return f"<Question {self.id} {self.type}>"


class QuestionOption(Base):
    """One choice of a multiple-choice question.

    ``is_correct`` is the answer key. No student-facing schema declares this field, so it
    cannot be serialised towards a student by accident (docs/api.md §4).
    """

    __tablename__ = "question_options"

    id: Mapped[int] = mapped_column(primary_key=True)
    question_id: Mapped[int] = mapped_column(
        ForeignKey("questions.id", ondelete="CASCADE"), nullable=False, index=True
    )
    option_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    option_image_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    display_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    is_correct: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    question: Mapped["Question"] = relationship(back_populates="options")
