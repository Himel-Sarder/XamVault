from __future__ import annotations

from sqlalchemy import Select, func, select
from sqlalchemy.orm import Session, selectinload

from app.models.attempt import ExamAttempt, StudentAnswer
from app.models.enums import AttemptStatus
from app.models.exam import Exam
from app.models.result import Result


class AttemptRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    # ---------------------------------------------------------------- lookups

    def get(self, attempt_id: int) -> ExamAttempt | None:
        return self.db.execute(
            select(ExamAttempt)
            .where(ExamAttempt.id == attempt_id)
            .execution_options(populate_existing=True)
            .options(selectinload(ExamAttempt.answers), selectinload(ExamAttempt.exam))
        ).scalar_one_or_none()

    def get_active_for(self, exam_id: int, student_id: int) -> ExamAttempt | None:
        return self.db.execute(
            select(ExamAttempt)
            .where(
                ExamAttempt.exam_id == exam_id,
                ExamAttempt.student_id == student_id,
                ExamAttempt.status == AttemptStatus.ACTIVE.value,
            )
            .options(selectinload(ExamAttempt.answers))
        ).scalar_one_or_none()

    def count_for(self, exam_id: int, student_id: int) -> int:
        """Every sitting, finished or not — this is what ``max_attempts`` limits."""
        return self.db.execute(
            select(func.count())
            .select_from(ExamAttempt)
            .where(ExamAttempt.exam_id == exam_id, ExamAttempt.student_id == student_id)
        ).scalar_one()

    def list_overdue(self, now, *, limit: int = 200) -> list[ExamAttempt]:
        """Active attempts whose window has passed, for the auto-submit sweep (§42)."""
        return list(
            self.db.execute(
                select(ExamAttempt)
                .where(
                    ExamAttempt.status == AttemptStatus.ACTIVE.value,
                    ExamAttempt.expires_at <= now,
                )
                .options(selectinload(ExamAttempt.answers))
                .limit(limit)
            )
            .scalars()
            .all()
        )

    def get_answer(self, attempt_id: int, exam_question_id: int) -> StudentAnswer | None:
        return self.db.execute(
            select(StudentAnswer).where(
                StudentAnswer.attempt_id == attempt_id,
                StudentAnswer.exam_question_id == exam_question_id,
            )
        ).scalar_one_or_none()

    # ---------------------------------------------------------------- results

    def get_result_for_attempt(self, attempt_id: int) -> Result | None:
        return self.db.execute(
            select(Result).where(Result.attempt_id == attempt_id)
        ).scalar_one_or_none()

    def get_result(self, result_id: int) -> Result | None:
        return self.db.execute(
            select(Result)
            .where(Result.id == result_id)
            .options(
                selectinload(Result.exam).selectinload(Exam.course),
                selectinload(Result.attempt),
                selectinload(Result.student),
            )
        ).scalar_one_or_none()

    def _result_query(self) -> Select:
        return select(Result).options(
            selectinload(Result.exam).selectinload(Exam.course),
            selectinload(Result.attempt),
            selectinload(Result.student),
        )

    def list_results_for_student(self, student_id: int, *, published_only: bool) -> list[Result]:
        stmt = self._result_query().where(Result.student_id == student_id)
        if published_only:
            stmt = stmt.where(Result.status == "published")
        return list(self.db.execute(stmt.order_by(Result.id.desc())).scalars().all())

    def list_results_for_exam(self, exam_id: int) -> list[Result]:
        from app.models.user import User

        stmt = (
            self._result_query()
            .where(Result.exam_id == exam_id)
            .options(selectinload(Result.student).selectinload(User.student_profile))
            .order_by(Result.total_score.desc(), Result.id)
        )
        return list(self.db.execute(stmt).scalars().all())

    # ---------------------------------------------------------------- writes

    def add(self, attempt: ExamAttempt) -> ExamAttempt:
        self.db.add(attempt)
        self.db.flush()
        return attempt

    def add_answer(self, answer: StudentAnswer) -> StudentAnswer:
        self.db.add(answer)
        self.db.flush()
        return answer

    def add_result(self, result: Result) -> Result:
        self.db.add(result)
        self.db.flush()
        return result
