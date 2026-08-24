"""Results: what a student may see of their own score, and what a teacher may see."""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy.orm import Session

from app.core.exceptions import ConflictError, NotFoundError
from app.models.enums import ResultStatus
from app.models.result import Result
from app.models.user import User
from app.repositories.attempt_repository import AttemptRepository
from app.repositories.exam_repository import ExamRepository
from app.services.notification_service import NotificationService
from app.schemas.result import (
    ResultStudent,
    ScoreBreakdown,
    StudentResultResponse,
    TeacherResultResponse,
)


class ResultService:
    def __init__(self, db: Session) -> None:
        self.db = db
        self.attempts = AttemptRepository(db)
        self.exams = ExamRepository(db)

    # --------------------------------------------------------- authorization

    def _exam_owned_by(self, exam_id: int, actor: User):
        exam = self.exams.get(exam_id)
        if exam is None:
            raise NotFoundError("Exam not found")
        if actor.is_admin or exam.teacher_id == actor.id:
            return exam
        raise NotFoundError("Exam not found")

    # ------------------------------------------------------------- student

    def list_mine(self, student: User) -> list[StudentResultResponse]:
        # published_only is not a filter applied afterwards - an unpublished result is
        # never loaded for a student at all (§44).
        results = self.attempts.list_results_for_student(student.id, published_only=True)
        return [self._student_view(result) for result in results]

    def get_mine(self, result_id: int, student: User) -> StudentResultResponse:
        result = self.attempts.get_result(result_id)
        if result is None or result.student_id != student.id:
            raise NotFoundError("Result not found")
        if not result.is_published:
            # Same 404 as "does not exist": a student learning that their result exists
            # but is withheld is itself a disclosure about the marking timetable.
            raise NotFoundError("Result not found")
        return self._student_view(result)

    # ------------------------------------------------------------- teacher

    def list_for_exam(self, exam_id: int, actor: User) -> list[TeacherResultResponse]:
        self._exam_owned_by(exam_id, actor)
        return [
            self._teacher_view(result) for result in self.attempts.list_results_for_exam(exam_id)
        ]

    def publish_for_exam(self, exam_id: int, actor: User) -> int:
        self._exam_owned_by(exam_id, actor)
        results = self.attempts.list_results_for_exam(exam_id)
        pending = [result for result in results if not result.is_published]
        if not pending:
            raise ConflictError(
                "There are no unpublished results for this exam", code="nothing_to_publish"
            )
        now = datetime.now(UTC)
        for result in pending:
            result.status = ResultStatus.PUBLISHED.value
            result.published_at = now

        # Only the students whose result actually moved — telling someone their result
        # is ready when it was already ready would be noise.
        NotificationService(self.db).results_published(
            pending[0].exam, [result.student_id for result in pending]
        )
        self.db.commit()
        return len(pending)

    # ------------------------------------------------------------- shaping

    @staticmethod
    def _scores(result: Result) -> ScoreBreakdown:
        return ScoreBreakdown(
            mcq=float(result.mcq_score),
            short_answer=float(result.short_answer_score),
            code=float(result.code_score),
        )

    def _student_view(self, result: Result) -> StudentResultResponse:
        return StudentResultResponse(
            id=result.id,
            exam_id=result.exam_id,
            exam_title=result.exam.title,
            course_code=result.exam.course.course_code,
            attempt_id=result.attempt_id,
            scores=self._scores(result),
            total_score=float(result.total_score),
            total_marks=result.exam.total_marks,
            percentage=float(result.percentage),
            status=result.status,
            submitted_at=result.attempt.submitted_at,
            published_at=result.published_at,
        )

    def _teacher_view(self, result: Result) -> TeacherResultResponse:
        profile = result.student.student_profile
        return TeacherResultResponse(
            id=result.id,
            exam_id=result.exam_id,
            attempt_id=result.attempt_id,
            student=ResultStudent(
                id=result.student.id,
                user_id=result.student.user_id,
                name=result.student.name,
                student_number=profile.student_id if profile else None,
            ),
            scores=self._scores(result),
            total_score=float(result.total_score),
            total_marks=result.exam.total_marks,
            percentage=float(result.percentage),
            status=result.status,
            submitted_at=result.attempt.submitted_at,
            published_at=result.published_at,
        )
