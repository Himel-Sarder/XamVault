from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, CheckConstraint, ForeignKey, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.models.enums import ROLE_CHECK_SQL, UserRole
from app.models.types import UTCDateTime, utcnow

if TYPE_CHECKING:
    from app.models.course import Course, CourseEnrollment
    from app.models.department import Department
    from app.models.refresh_token import RefreshToken


class User(Base):
    """A login identity. Role-specific attributes live in the profile tables."""

    __tablename__ = "users"
    __table_args__ = (
        CheckConstraint(ROLE_CHECK_SQL, name="role"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[str] = mapped_column(String(50), unique=True, nullable=False, index=True)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    name: Mapped[str] = mapped_column(String(150), nullable=False)
    email: Mapped[str | None] = mapped_column(String(255), unique=True, nullable=True)
    role: Mapped[str] = mapped_column(String(20), nullable=False, index=True)
    department_id: Mapped[int | None] = mapped_column(
        ForeignKey("departments.id", ondelete="SET NULL"), nullable=True, index=True
    )
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utcnow, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime,
        nullable=False,
        default=utcnow,
        onupdate=utcnow,
        server_default=func.now(),
    )

    department: Mapped["Department | None"] = relationship(back_populates="users")
    student_profile: Mapped["StudentProfile | None"] = relationship(
        back_populates="user", cascade="all, delete-orphan", uselist=False
    )
    teacher_profile: Mapped["TeacherProfile | None"] = relationship(
        back_populates="user", cascade="all, delete-orphan", uselist=False
    )
    refresh_tokens: Mapped[list["RefreshToken"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    created_courses: Mapped[list["Course"]] = relationship(back_populates="creator")
    enrollments: Mapped[list["CourseEnrollment"]] = relationship(
        back_populates="student", cascade="all, delete-orphan"
    )

    @property
    def is_admin(self) -> bool:
        return self.role == UserRole.ADMIN

    @property
    def is_teacher(self) -> bool:
        return self.role == UserRole.TEACHER

    @property
    def is_student(self) -> bool:
        return self.role == UserRole.STUDENT

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return f"<User {self.user_id} ({self.role})>"


class StudentProfile(Base):
    __tablename__ = "student_profiles"
    __table_args__ = (
        CheckConstraint(
            "study_year IS NULL OR (study_year >= 1 AND study_year <= 4)",
            name="study_year",
        ),
        CheckConstraint(
            "semester IS NULL OR (semester >= 1 AND semester <= 2)", name="semester"
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False
    )
    student_id: Mapped[str] = mapped_column(String(50), unique=True, nullable=False)
    department_id: Mapped[int | None] = mapped_column(
        ForeignKey("departments.id", ondelete="SET NULL"), nullable=True
    )
    #: Year of the programme, 1 to 4.
    #:
    #: Named study_year rather than year because ``session`` next to it already holds
    #: the academic year as "2025-2026", and two fields both called some kind of year
    #: would be read wrongly at least once. The UI label is simply "Year".
    study_year: Mapped[int | None] = mapped_column(Integer, nullable=True)

    #: Which half of that year, 1 or 2.
    semester: Mapped[int | None] = mapped_column(Integer, nullable=True)
    session: Mapped[str | None] = mapped_column(String(20), nullable=True)

    user: Mapped["User"] = relationship(back_populates="student_profile")


class TeacherProfile(Base):
    __tablename__ = "teacher_profiles"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False
    )
    teacher_id: Mapped[str] = mapped_column(String(50), unique=True, nullable=False)
    department_id: Mapped[int | None] = mapped_column(
        ForeignKey("departments.id", ondelete="SET NULL"), nullable=True
    )
    designation: Mapped[str | None] = mapped_column(String(100), nullable=True)

    user: Mapped["User"] = relationship(back_populates="teacher_profile")
