from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

AttemptStatusLiteral = Literal["active", "submitted", "auto_submitted", "terminated"]


class AttemptOptionResponse(BaseModel):
    """One option as the student sees it.

    ``is_correct`` is not declared here at all, so no refactor can leak the answer key
    into a paper a student is sitting (docs/api.md §4).
    """

    id: int
    option_text: str | None
    option_image_url: str | None


class AttemptQuestionResponse(BaseModel):
    """A question inside an attempt, in this student's personal order."""

    exam_question_id: int
    position: int = Field(description="1-based position in this student's paper.")
    type: str
    question_text: str
    question_image_url: str | None
    marks: int
    options: list[AttemptOptionResponse]
    selected_option_id: int | None = Field(
        default=None, description="Chosen option, for the multiple-choice types."
    )
    answer_text: str | None = Field(
        default=None, description="Written answer, for short-answer and code questions."
    )

    # CODE_ANSWER only: shown beside the editor so the rules are visible.
    language: str | None = None
    time_limit_seconds: int | None = None
    memory_limit_mb: int | None = None


class AttemptResponse(BaseModel):
    """Everything needed to render — or restore — an exam in progress (§60)."""

    id: int
    exam_id: int
    exam_title: str
    course_code: str
    status: AttemptStatusLiteral
    started_at: datetime
    expires_at: datetime
    submitted_at: datetime | None

    # Authoritative. The client's countdown is cosmetic and is re-synced from this on
    # every request (§34).
    remaining_seconds: int
    server_time: datetime

    duration_minutes: int
    total_marks: int
    allow_back_navigation: bool

    # Tells the app whether to engage device lockdown for this exam (§37).
    secure_mode: bool
    questions: list[AttemptQuestionResponse]
    answered_count: int
    total_questions: int


class AnswerSubmit(BaseModel):
    """One of the two shapes, depending on the question type.

    ``selected_option_id: null`` clears a choice; an empty ``answer_text`` clears a
    written answer. The server checks which shape the question actually takes.
    """

    exam_question_id: int
    selected_option_id: int | None = None
    answer_text: str | None = Field(default=None, max_length=50_000)


class AnswerAck(BaseModel):
    """Deliberately small — this is sent on every tap and every pause in typing."""

    exam_question_id: int
    selected_option_id: int | None
    answer_text: str | None
    answered_count: int
    remaining_seconds: int


class SubmitResponse(BaseModel):
    attempt_id: int
    status: AttemptStatusLiteral
    submitted_at: datetime
    answered_count: int
    total_questions: int
    # Present only when the exam is set to show results immediately (§27).
    result_id: int | None = None
