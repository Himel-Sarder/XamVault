from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

from app.schemas.common import ORMModel

JoinRequestStatusLiteral = Literal["pending", "approved", "rejected"]


class JoinRequestStudent(ORMModel):
    """Who is asking. Enough for a teacher to recognise the student, nothing more."""

    id: int
    user_id: str
    name: str
    student_number: str | None = None


class JoinRequestResponse(ORMModel):
    """Teacher-facing view of one request."""

    id: int
    exam_id: int
    status: JoinRequestStatusLiteral
    requested_at: datetime
    reviewed_at: datetime | None
    reviewed_by: int | None
    student: JoinRequestStudent


class StudentJoinRequestResponse(BaseModel):
    """The student's own request, with enough context to be readable in a list."""

    id: int
    exam_id: int
    exam_title: str
    course_code: str
    status: JoinRequestStatusLiteral
    requested_at: datetime
    reviewed_at: datetime | None


class BulkReviewRequest(BaseModel):
    """Restricting a bulk action to the ids the teacher actually saw stops a request
    that was created after the screen loaded from being swept up unseen."""

    request_ids: list[int] | None = Field(
        default=None,
        description="Limit the action to these requests. Omit to apply to all pending.",
    )


class BulkReviewResponse(BaseModel):
    updated: int
    status: JoinRequestStatusLiteral
