"""Persistence for users and their role profiles.

Repositories answer "what rows exist"; they never decide who is allowed to see them —
that belongs to the service layer.
"""

from __future__ import annotations

from sqlalchemy import Select, func, select
from sqlalchemy.orm import Session, selectinload

from app.models.enums import UserRole
from app.models.user import StudentProfile, TeacherProfile, User


class UserRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    # ---------------------------------------------------------------- lookups

    def get(self, user_id: int) -> User | None:
        return self.db.get(User, user_id)

    def get_with_profiles(self, user_id: int) -> User | None:
        stmt = (
            select(User)
            .where(User.id == user_id)
            .options(
                selectinload(User.student_profile),
                selectinload(User.teacher_profile),
                selectinload(User.department),
            )
        )
        return self.db.execute(stmt).scalar_one_or_none()

    def get_by_login_id(self, login_id: str) -> User | None:
        return self.db.execute(
            select(User).where(User.user_id == login_id)
        ).scalar_one_or_none()

    def get_many_by_login_id(self, login_ids: list[str]) -> dict[str, User]:
        """One query for a whole roll list, keyed by login id.

        Calling :meth:`get_by_login_id` in a loop would issue one round trip per row,
        which a two-hundred-name paste can ill afford.
        """
        if not login_ids:
            return {}
        rows = self.db.execute(
            select(User).where(User.user_id.in_(login_ids))
        ).scalars().all()
        return {user.user_id: user for user in rows}

    def get_by_email(self, email: str) -> User | None:
        return self.db.execute(
            select(User).where(User.email == email)
        ).scalar_one_or_none()

    def student_id_taken(self, student_id: str) -> bool:
        return self.db.execute(
            select(func.count()).select_from(StudentProfile).where(
                StudentProfile.student_id == student_id
            )
        ).scalar_one() > 0

    def teacher_id_taken(self, teacher_id: str) -> bool:
        return self.db.execute(
            select(func.count()).select_from(TeacherProfile).where(
                TeacherProfile.teacher_id == teacher_id
            )
        ).scalar_one() > 0

    # ---------------------------------------------------------------- listing

    def _list_query(self, role: str | None, search: str | None) -> Select:
        stmt = select(User)
        if role:
            stmt = stmt.where(User.role == role)
        if search:
            pattern = f"%{search.lower()}%"
            stmt = stmt.where(
                func.lower(User.name).like(pattern) | func.lower(User.user_id).like(pattern)
            )
        return stmt

    def students_at_stage(
        self,
        *,
        study_year: int | None,
        semester: int | None,
        department_id: int | None,
        search: str | None,
        exclude_ids: set[int],
        limit: int,
    ) -> list[User]:
        """Active students filed at a given point in the programme.

        Ordered by student id, which is how a roll list is read, rather than by row id.
        """
        stmt = (
            select(User)
            .join(StudentProfile, StudentProfile.user_id == User.id)
            .where(User.role == UserRole.STUDENT, User.is_active.is_(True))
            .options(selectinload(User.student_profile))
        )
        if study_year is not None:
            stmt = stmt.where(StudentProfile.study_year == study_year)
        if semester is not None:
            stmt = stmt.where(StudentProfile.semester == semester)
        if department_id is not None:
            # The profile's department, falling back to the account's, because a
            # student created before departments were on the profile has only the one.
            #
            # A student with no department at all is still offered. Narrowing to the
            # course's department is a convenience, not a rule, and excluding the
            # unassigned makes them invisible for a reason that has nothing to do with
            # the year the teacher picked -- which is exactly what happened when the
            # departments were deleted and every student's became null.
            stmt = stmt.where(
                (StudentProfile.department_id == department_id)
                | (
                    StudentProfile.department_id.is_(None)
                    & (User.department_id == department_id)
                )
                | (
                    StudentProfile.department_id.is_(None)
                    & User.department_id.is_(None)
                )
            )
        if search:
            pattern = f"%{search.lower()}%"
            stmt = stmt.where(
                func.lower(User.name).like(pattern)
                | func.lower(StudentProfile.student_id).like(pattern)
                | func.lower(User.user_id).like(pattern)
            )
        if exclude_ids:
            stmt = stmt.where(User.id.notin_(exclude_ids))

        return list(
            self.db.execute(stmt.order_by(StudentProfile.student_id).limit(limit))
            .scalars()
            .all()
        )

    def list_paged(
        self, *, role: str | None, search: str | None, offset: int, limit: int
    ) -> tuple[list[User], int]:
        base = self._list_query(role, search)
        total = self.db.execute(
            select(func.count()).select_from(base.subquery())
        ).scalar_one()
        rows = (
            self.db.execute(base.order_by(User.id).offset(offset).limit(limit))
            .scalars()
            .all()
        )
        return list(rows), total

    # ---------------------------------------------------------------- writes

    def add(self, user: User) -> User:
        self.db.add(user)
        self.db.flush()
        return user

    def add_student_profile(self, profile: StudentProfile) -> StudentProfile:
        self.db.add(profile)
        self.db.flush()
        return profile

    def add_teacher_profile(self, profile: TeacherProfile) -> TeacherProfile:
        self.db.add(profile)
        self.db.flush()
        return profile
