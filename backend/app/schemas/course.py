from __future__ import annotations

from datetime import datetime

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
