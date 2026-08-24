from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel

ResultStatusLiteral = Literal["pending", "published"]


class ScoreBreakdown(BaseModel):
    """Split by question kind because each is graded by a different mechanism (§43)."""

    mcq: float
    short_answer: float
    code: float


class StudentResultResponse(BaseModel):
    """A student's own result. Only ever returned once it is published (§44)."""

    id: int
    exam_id: int
    exam_title: str
    course_code: str
    attempt_id: int
    scores: ScoreBreakdown
    total_score: float
    total_marks: int
    percentage: float
    status: ResultStatusLiteral
    submitted_at: datetime | None
    published_at: datetime | None


class ResultStudent(BaseModel):
    id: int
    user_id: str
    name: str
    student_number: str | None = None


class TeacherResultResponse(BaseModel):
    """The same result seen by the teacher who owns the exam, plus who it belongs to."""

    id: int
    exam_id: int
    attempt_id: int
    student: ResultStudent
    scores: ScoreBreakdown
    total_score: float
    total_marks: int
    percentage: float
    status: ResultStatusLiteral
    submitted_at: datetime | None
    published_at: datetime | None


class PublishResultsResponse(BaseModel):
    published: int
