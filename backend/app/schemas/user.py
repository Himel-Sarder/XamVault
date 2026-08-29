from __future__ import annotations

import re
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, EmailStr, Field, model_validator

from app.models.enums import UserRole
from app.schemas.common import ORMModel
from app.schemas.department import DepartmentResponse

RoleLiteral = Literal["admin", "teacher", "student"]

PASSWORD_MIN_LENGTH = 8
PASSWORD_MAX_LENGTH = 128

#: A student signs in with their student number, which this university issues as
#: eight digits. Enforced on creation so a typo becomes an error at the point it is
#: made, rather than an account nobody can sign in to.
STUDENT_ID_LENGTH = 8
STUDENT_ID_PATTERN = re.compile(rf"\d{{{STUDENT_ID_LENGTH}}}")


class UserSummary(ORMModel):
    """The compact user object embedded in the login response."""

    id: int
    user_id: str
    name: str
    role: RoleLiteral


class StudentProfileResponse(ORMModel):
    student_id: str
    department_id: int | None
    study_year: int | None
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
    study_year: int | None = Field(default=None, ge=1, le=4, description="Year of the programme, 1 to 4.")
    semester: int | None = Field(default=None, ge=1, le=2, description="Which half of that year, 1 or 2.")
    session: str | None = Field(default=None, max_length=20)
    teacher_id: str | None = Field(default=None, max_length=50)
    designation: str | None = Field(default=None, max_length=100)

    @model_validator(mode="after")
    def _require_profile_fields_for_role(self) -> "UserCreate":
        if self.role == UserRole.STUDENT:
            if not STUDENT_ID_PATTERN.fullmatch(self.user_id):
                raise ValueError(
                    "A student signs in with their 8-digit student ID, "
                    f"so user_id must be exactly {STUDENT_ID_LENGTH} digits"
                )
            # The registration number and the login are the same number here, so an
            # admin is not asked to type it twice. It stays settable for the case where
            # an institution genuinely keeps them apart.
            if not self.student_id:
                self.student_id = self.user_id
        if self.role == UserRole.TEACHER and not self.teacher_id:
            self.teacher_id = self.user_id
        return self


class UserUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=150)
    email: EmailStr | None = None
    department_id: int | None = None
    is_active: bool | None = None
