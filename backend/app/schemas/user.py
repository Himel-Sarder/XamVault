from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, EmailStr, Field, model_validator

from app.models.enums import UserRole
from app.schemas.common import ORMModel
from app.schemas.department import DepartmentResponse

RoleLiteral = Literal["admin", "teacher", "student"]

PASSWORD_MIN_LENGTH = 8
PASSWORD_MAX_LENGTH = 128


class UserSummary(ORMModel):
    """The compact user object embedded in the login response."""

    id: int
    user_id: str
    name: str
    role: RoleLiteral


class StudentProfileResponse(ORMModel):
    student_id: str
    department_id: int | None
    semester: int | None
    session: str | None


class TeacherProfileResponse(ORMModel):
    teacher_id: str
    department_id: int | None
    designation: str | None


class UserResponse(ORMModel):
    """Note the absence of ``password_hash`` — it is not declared anywhere in this module,
    so no route can serialise it by accident."""

    id: int
    user_id: str
    name: str
    email: str | None
    role: RoleLiteral
    department_id: int | None
    is_active: bool
    created_at: datetime


class UserDetailResponse(UserResponse):
    department: DepartmentResponse | None = None
    student_profile: StudentProfileResponse | None = None
    teacher_profile: TeacherProfileResponse | None = None


class UserCreate(BaseModel):
    """Admin-only. ``is_active`` and ``id`` are server-owned and deliberately absent."""

    user_id: str = Field(min_length=3, max_length=50)
    password: str = Field(min_length=PASSWORD_MIN_LENGTH, max_length=PASSWORD_MAX_LENGTH)
    name: str = Field(min_length=1, max_length=150)
    email: EmailStr | None = None
    role: RoleLiteral
    department_id: int | None = None

    # Role-specific profile fields.
    student_id: str | None = Field(default=None, max_length=50)
    semester: int | None = Field(default=None, ge=1, le=12)
    session: str | None = Field(default=None, max_length=20)
    teacher_id: str | None = Field(default=None, max_length=50)
    designation: str | None = Field(default=None, max_length=100)

    @model_validator(mode="after")
    def _require_profile_fields_for_role(self) -> "UserCreate":
        if self.role == UserRole.STUDENT and not self.student_id:
            raise ValueError("student_id is required when role is 'student'")
        if self.role == UserRole.TEACHER and not self.teacher_id:
            raise ValueError("teacher_id is required when role is 'teacher'")
        return self


class UserUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=150)
    email: EmailStr | None = None
    department_id: int | None = None
    is_active: bool | None = None
