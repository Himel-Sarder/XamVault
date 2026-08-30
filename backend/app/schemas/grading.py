from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class GradingQueueEntry(BaseModel):
    """One submitted attempt, and how much marking it still needs."""

    attempt_id: int
    student_id: int
    student_name: str
    student_number: str
    submitted_at: datetime | None
    awaiting_marks: int
    total_score: float
    total_marks: int


class AnswerToMark(BaseModel):
    """One answer a person has to read, beside the question it answers."""

    answer_id: int | None
    exam_question_id: int
    position: int
    type: Literal["SHORT_ANSWER", "CODE_ANSWER"]
    question_text: str
    language: str | None
    max_marks: int
    answer_text: str | None

    #: Kept for answers recorded while photograph questions existed.
    answer_image_urls: list[str] = Field(default_factory=list)
    marks_awarded: float | None
    feedback: str | None
    status: Literal["pending", "evaluated"]


class AttemptGradingResponse(BaseModel):
    attempt_id: int
    exam_id: int
    exam_title: str
    student_name: str
    submitted_at: datetime | None
    awaiting_marks: int
    answers: list[AnswerToMark]


class EvaluateAnswerRequest(BaseModel):
    """The upper bound is the question's own marks, checked server-side against the
    snapshot — a teacher cannot award 20 out of 10."""

    marks_awarded: float = Field(ge=0, le=100)
    feedback: str | None = Field(default=None, max_length=5000)


class EvaluatedAnswerResponse(BaseModel):
    answer_id: int
    exam_question_id: int
    marks_awarded: float
    feedback: str | None
    status: Literal["pending", "evaluated"]
    awaiting_marks: int
    total_score: float
