from __future__ import annotations

from datetime import datetime

from sqlalchemy import Select, func, select
from sqlalchemy.orm import Session, selectinload

from app.models.course import Course, CourseEnrollment
from app.models.enums import ExamStatus
from app.models.exam import Exam, ExamQuestion, ExamSettings
from app.models.question import Question


class ExamRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    # ---------------------------------------------------------------- lookups

    def get(self, exam_id: int) -> Exam | None:
        return self.db.get(Exam, exam_id)

    def get_full(self, exam_id: int) -> Exam | None:
        """Exam with settings and ordered questions, in a fixed number of queries.

        ``populate_existing`` matters here: if the session already holds this Exam with a
        loaded ``questions`` collection, SQLAlchemy would hand back the cached one and the
        response would report a stale question count right after adding a question.
        """
        stmt = (
            select(Exam)
            .where(Exam.id == exam_id)
            .execution_options(populate_existing=True)
            .options(
                selectinload(Exam.settings),
                selectinload(Exam.questions)
                .selectinload(ExamQuestion.question)
                .selectinload(Question.options),
            )
        )
        return self.db.execute(stmt).scalar_one_or_none()

    def _teacher_query(self, teacher_id: int | None) -> Select:
        """``None`` means "every exam" - used for admins, who may already open any
        single exam, so the list must not show them nothing."""
        stmt = select(Exam)
        return stmt if teacher_id is None else stmt.where(Exam.teacher_id == teacher_id)

    def list_for_teacher(
        self,
        teacher_id: int | None,
        *,
        course_id: int | None,
        status: str | None,
        offset: int,
        limit: int,
    ) -> tuple[list[Exam], int]:
        base = self._teacher_query(teacher_id)
        if course_id is not None:
            base = base.where(Exam.course_id == course_id)
        if status is not None:
            base = base.where(Exam.status == status)
        total = self.db.execute(
            select(func.count()).select_from(base.subquery())
        ).scalar_one()
        rows = (
            self.db.execute(
                # questions are eager-loaded so the list can report question_count
                # without an extra query per exam.
                base.options(selectinload(Exam.settings), selectinload(Exam.questions))
                .order_by(Exam.created_at.desc(), Exam.id.desc())
                .offset(offset)
                .limit(limit)
            )
            .scalars()
            .all()
        )
        return list(rows), total

    # ----------------------------------------------------- student discovery

    def _student_visible_query(self, student_id: int) -> Select:
        """Published exams in courses this student is enrolled in.

        Both conditions live in the query. Fetching all exams and filtering afterwards
        would mean one forgotten check exposes another cohort's paper.
        """
        return (
            select(Exam)
            .join(CourseEnrollment, CourseEnrollment.course_id == Exam.course_id)
            .join(Course, Course.id == Exam.course_id)
            .where(
                CourseEnrollment.student_id == student_id,
                Exam.status == ExamStatus.PUBLISHED.value,
                Course.is_active.is_(True),
            )
        )

    def list_available_for_student(
        self, student_id: int, *, now: datetime, offset: int, limit: int, include_closed: bool
    ) -> tuple[list[Exam], int]:
        base = self._student_visible_query(student_id)
        if not include_closed:
            # §29: only what is running or still to come.
            base = base.where((Exam.expires_at.is_(None)) | (Exam.expires_at > now))
        total = self.db.execute(
            select(func.count()).select_from(base.subquery())
        ).scalar_one()
        rows = (
            self.db.execute(
                base.options(
                    selectinload(Exam.settings),
                    selectinload(Exam.questions),
                    selectinload(Exam.course),
                )
                .order_by(Exam.start_at.asc().nulls_last(), Exam.id)
                .offset(offset)
                .limit(limit)
            )
            .scalars()
            .all()
        )
        return list(rows), total

    def get_for_student(self, exam_id: int, student_id: int) -> Exam | None:
        stmt = (
            self._student_visible_query(student_id)
            .where(Exam.id == exam_id)
            .execution_options(populate_existing=True)
            .options(
                selectinload(Exam.settings),
                selectinload(Exam.questions),
                selectinload(Exam.course),
            )
        )
        return self.db.execute(stmt).scalar_one_or_none()

    # ------------------------------------------------------------- questions

    def count_questions(self, exam_id: int) -> int:
        return self.db.execute(
            select(func.count()).select_from(ExamQuestion).where(
                ExamQuestion.exam_id == exam_id
            )
        ).scalar_one()

    def sum_marks(self, exam_id: int) -> int:
        total = self.db.execute(
            select(func.coalesce(func.sum(ExamQuestion.marks_snapshot), 0)).where(
                ExamQuestion.exam_id == exam_id
            )
        ).scalar_one()
        return int(total)

    def next_display_order(self, exam_id: int) -> int:
        highest = self.db.execute(
            select(func.coalesce(func.max(ExamQuestion.display_order), -1)).where(
                ExamQuestion.exam_id == exam_id
            )
        ).scalar_one()
        return int(highest) + 1

    def get_exam_question(self, exam_id: int, exam_question_id: int) -> ExamQuestion | None:
        return self.db.execute(
            select(ExamQuestion).where(
                ExamQuestion.id == exam_question_id, ExamQuestion.exam_id == exam_id
            )
        ).scalar_one_or_none()

    def list_exam_questions(self, exam_id: int) -> list[ExamQuestion]:
        stmt = (
            select(ExamQuestion)
            .where(ExamQuestion.exam_id == exam_id)
            .order_by(ExamQuestion.display_order, ExamQuestion.id)
        )
        return list(self.db.execute(stmt).scalars().all())

    # ---------------------------------------------------------------- writes

    def add(self, exam: Exam) -> Exam:
        self.db.add(exam)
        self.db.flush()
        return exam

    def add_settings(self, settings: ExamSettings) -> ExamSettings:
        self.db.add(settings)
        self.db.flush()
        return settings

    def add_exam_question(self, link: ExamQuestion) -> ExamQuestion:
        self.db.add(link)
        self.db.flush()
        return link

    def delete_exam_question(self, link: ExamQuestion) -> None:
        self.db.delete(link)
        self.db.flush()

    def delete(self, exam: Exam) -> None:
        self.db.delete(exam)
        self.db.flush()
