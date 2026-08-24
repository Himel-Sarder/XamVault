from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

from app.schemas.common import ORMModel
from app.schemas.user import UserSummary


class CourseCreate(BaseModel):
    """``created_by`` is taken from the authenticated user, never from the request."""

    course_code: str = Field(min_length=1, max_length=30)
    course_name: str = Field(min_length=1, max_length=200)
    department_id: int | None = None
    semester: int | None = Field(default=None, ge=1, le=12)
    session: str | None = Field(default=None, max_length=20)


class CourseUpdate(BaseModel):
    course_name: str | None = Field(default=None, min_length=1, max_length=200)
    department_id: int | None = None
    semester: int | None = Field(default=None, ge=1, le=12)
    session: str | None = Field(default=None, max_length=20)
    is_active: bool | None = None


class CourseResponse(ORMModel):
    id: int
    course_code: str
    course_name: str
    department_id: int | None
    semester: int | None
    session: str | None
    created_by: int
    is_active: bool
    created_at: datetime


class EnrollmentCreate(BaseModel):
    """Identifies the student by their login id, which is what a teacher actually has."""

    student_user_id: str = Field(min_length=1, max_length=50)


class EnrollmentResponse(ORMModel):
    id: int
    course_id: int
    student_id: int
    created_at: datetime
    student: UserSummary | None = None


MAX_BULK_ENROLMENT = 200


class BulkEnrollmentCreate(BaseModel):
    """A roll list, as a teacher actually holds it: login ids, pasted in bulk."""

    student_user_ids: list[str] = Field(
        min_length=1,
        max_length=MAX_BULK_ENROLMENT,
        description=(
            f"Student login ids, at most {MAX_BULK_ENROLMENT} per request. "
            "Duplicates within the list are collapsed."
        ),
    )


SkipReason = Literal["not_found", "not_a_student", "deactivated", "already_enrolled"]


class SkippedEnrolment(BaseModel):
    """Why one id in the batch produced no enrolment.

    A teacher pasting sixty ids needs to know *which* three failed and why. Returning
    only a count would send them back to compare two lists by eye.
    """

    student_user_id: str
    reason: SkipReason


class BulkEnrollmentResponse(BaseModel):
    """Enrolled and skipped are reported together.

    Unlike the bulk join-request review, a partially successful batch is the expected
    case rather than a failure: a typo in one id is no reason to refuse the other
    fifty-nine. Nothing is half-written -- the whole batch commits once -- but a
    rejected id is an outcome here, not an error that aborts.
    """

    enrolled: list[UserSummary]
    skipped: list[SkippedEnrolment]

    @property
    def enrolled_count(self) -> int:
        return len(self.enrolled)
