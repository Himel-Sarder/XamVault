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
    study_year: int | None = Field(default=None, ge=1, le=4, description="Year of the programme, 1 to 4.")
    semester: int | None = Field(default=None, ge=1, le=2, description="Which half of that year, 1 or 2.")
    session: str | None = Field(default=None, max_length=20)


class CourseUpdate(BaseModel):
    course_name: str | None = Field(default=None, min_length=1, max_length=200)
    department_id: int | None = None
    study_year: int | None = Field(default=None, ge=1, le=4, description="Year of the programme, 1 to 4.")
    semester: int | None = Field(default=None, ge=1, le=2, description="Which half of that year, 1 or 2.")
    session: str | None = Field(default=None, max_length=20)
    is_active: bool | None = None


class CourseResponse(ORMModel):
    id: int
    course_code: str
    course_name: str
    department_id: int | None
    study_year: int | None
    semester: int | None
    session: str | None
    created_by: int

    #: Who runs it, by name. An administrator assigning courses needs to see the current
    #: holder without resolving an integer against the user directory by hand.
    teacher_name: str | None = None
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


class CourseAssign(BaseModel):
    """Hand a course to a teacher. Identified by login id, which is what an admin has."""

    teacher_user_id: str = Field(min_length=1, max_length=50)


class CourseAssignResponse(BaseModel):
    """The course as it now stands, and what deliberately did not move with it."""

    course: CourseResponse

    #: Exams on this course still authored by whoever held it before.
    #:
    #: Reassigning does not rewrite authorship of work already done: an exam is
    #: somebody's, and its results point at them. Reporting the count means an
    #: administrator learns that from the response rather than from a teacher who
    #: cannot open a paper they expected to inherit.
    exams_kept_by_previous_teacher: int
