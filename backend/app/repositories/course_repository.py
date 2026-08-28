from __future__ import annotations

from sqlalchemy import Select, func, select
from sqlalchemy.orm import Session, selectinload

from app.models.course import Course, CourseEnrollment
from app.models.enums import UserRole
from app.models.user import User


class CourseRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    # ---------------------------------------------------------------- lookups

    def get(self, course_id: int) -> Course | None:
        return self.db.get(Course, course_id)

    def get_by_code_and_session(self, course_code: str, session: str | None) -> Course | None:
        """Find a duplicate of ``(course_code, session)``.

        The unique constraint cannot catch a repeated NULL session — SQL treats NULLs as
        distinct — so the service checks here explicitly before inserting.
        """
        session_match = Course.session.is_(None) if session is None else Course.session == session
        stmt = select(Course).where(Course.course_code == course_code, session_match)
        return self.db.execute(stmt).scalar_one_or_none()

    # ---------------------------------------------------------------- listing

    def _visible_query(self, viewer: User) -> Select:
        """Scope courses inside the query, not by filtering results afterwards.

        Filtering after the fact means the rows were already loaded, and one forgotten
        filter leaks another teacher's data.
        """
        stmt = select(Course)
        if viewer.role == UserRole.STUDENT:
            return stmt.join(
                CourseEnrollment, CourseEnrollment.course_id == Course.id
            ).where(CourseEnrollment.student_id == viewer.id)
        if viewer.role == UserRole.TEACHER:
            return stmt.where(Course.created_by == viewer.id)
        return stmt  # admin

    def list_visible_paged(
        self, viewer: User, *, offset: int, limit: int, active_only: bool = False
    ) -> tuple[list[Course], int]:
        # creator is rendered on every row, so load it with the page rather than
        # issuing one query per course.
        base = self._visible_query(viewer).options(selectinload(Course.creator))
        if active_only:
            base = base.where(Course.is_active.is_(True))
        total = self.db.execute(
            select(func.count()).select_from(base.subquery())
        ).scalar_one()
        rows = (
            self.db.execute(base.order_by(Course.course_code).offset(offset).limit(limit))
            .scalars()
            .all()
        )
        return list(rows), total

    def is_visible_to(self, course_id: int, viewer: User) -> bool:
        stmt = self._visible_query(viewer).where(Course.id == course_id)
        return (
            self.db.execute(select(func.count()).select_from(stmt.subquery())).scalar_one()
            > 0
        )

    # ------------------------------------------------------------ enrollments

    def get_enrollment(self, course_id: int, student_id: int) -> CourseEnrollment | None:
        return self.db.execute(
            select(CourseEnrollment).where(
                CourseEnrollment.course_id == course_id,
                CourseEnrollment.student_id == student_id,
            )
        ).scalar_one_or_none()

    def enrolled_student_ids(self, course_id: int, student_ids: list[int]) -> set[int]:
        """Which of these students already hold a place on the course."""
        if not student_ids:
            return set()
        rows = self.db.execute(
            select(CourseEnrollment.student_id).where(
                CourseEnrollment.course_id == course_id,
                CourseEnrollment.student_id.in_(student_ids),
            )
        ).scalars().all()
        return set(rows)

    def list_enrollments(self, course_id: int) -> list[CourseEnrollment]:
        stmt = (
            select(CourseEnrollment)
            .where(CourseEnrollment.course_id == course_id)
            .options(selectinload(CourseEnrollment.student))
            .order_by(CourseEnrollment.id)
        )
        return list(self.db.execute(stmt).scalars().all())

    # ---------------------------------------------------------------- writes

    def add(self, course: Course) -> Course:
        self.db.add(course)
        self.db.flush()
        return course

    def add_enrollment(self, enrollment: CourseEnrollment) -> CourseEnrollment:
        self.db.add(enrollment)
        self.db.flush()
        return enrollment

    def delete_enrollment(self, enrollment: CourseEnrollment) -> None:
        self.db.delete(enrollment)
        self.db.flush()
