from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

from app.schemas.common import ORMModel

MIN_DURATION_MINUTES = 1
MAX_DURATION_MINUTES = 24 * 60


class ExamSettingsUpdate(BaseModel):
    shuffle_questions: bool | None = None
    shuffle_answers: bool | None = None
    allow_back_navigation: bool | None = None
    auto_submit: bool | None = None
    secure_mode: bool | None = None
    show_result_immediately: bool | None = None
    max_attempts: int | None = Field(default=None, ge=1, le=10)


class ExamSettingsResponse(ORMModel):
    shuffle_questions: bool
    shuffle_answers: bool
    allow_back_navigation: bool
    auto_submit: bool
    secure_mode: bool
    show_result_immediately: bool
    max_attempts: int


class ExamCreate(BaseModel):
    """Note what is absent: ``teacher_id``, ``status``, ``total_marks`` and
    ``expires_at`` are all server-owned (docs/security.md §3), so a client cannot
    propose them even by sending them."""

    course_id: int
    title: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=5000)
    start_at: datetime | None = None
    duration_minutes: int = Field(ge=MIN_DURATION_MINUTES, le=MAX_DURATION_MINUTES)
    settings: ExamSettingsUpdate | None = None


class ExamUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=5000)
    start_at: datetime | None = None
    duration_minutes: int | None = Field(
        default=None, ge=MIN_DURATION_MINUTES, le=MAX_DURATION_MINUTES
    )


class TeacherExamResponse(ORMModel):
    id: int
    course_id: int
    teacher_id: int
    title: str
    description: str | None
    start_at: datetime | None
    duration_minutes: int
    expires_at: datetime | None
    total_marks: int
    status: Literal["draft", "published", "running", "completed", "cancelled"]
    created_at: datetime
    published_at: datetime | None
    question_count: int
    settings: ExamSettingsResponse | None = None


class PublishIssue(BaseModel):
    """One reason an exam cannot be published, addressed to the teacher."""

    field: str
    message: str


class PublishCheckResponse(BaseModel):
    """Lets the UI grey out Publish and say why, without the teacher having to try it."""

    can_publish: bool
    issues: list[PublishIssue]


# --------------------------------------------------------------- student view


class StudentExamSettings(BaseModel):
    """The settings a student needs to know about before starting.

    ``shuffle_questions`` / ``shuffle_answers`` are deliberately absent: they are the
    teacher's anti-collusion configuration and tell a student nothing useful.
    """

    secure_mode: bool
    allow_back_navigation: bool
    max_attempts: int


class StudentExamResponse(BaseModel):
    """A published exam as a student sees it.

    A different class from :class:`TeacherExamResponse` rather than the same one with
    fields removed, so ``teacher_id``, draft state and per-student statistics cannot leak
    by omission (docs/api.md §4).
    """

    id: int
    course_id: int
    course_code: str
    course_name: str
    title: str
    description: str | None
    start_at: datetime | None
    duration_minutes: int
    expires_at: datetime | None
    total_marks: int
    question_count: int

    # Server-computed state; the client renders it, it does not decide it.
    availability: Literal["upcoming", "open", "closed"]
    join_request_status: Literal["none", "pending", "approved", "rejected"]
    can_request_join: bool
    settings: StudentExamSettings
