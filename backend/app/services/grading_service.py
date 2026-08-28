"""Phases 14-15 — a teacher marking what a machine cannot.

Short answers and code submissions are left ``pending`` at submission. This is where a
person awards the marks, and where the result is rebuilt afterwards so a total is always
the sum of what has actually been awarded.
"""

from __future__ import annotations

from datetime import UTC, datetime
from decimal import Decimal
from typing import Any

from sqlalchemy.orm import Session

from app.core.exceptions import ConflictError, InvalidRequestError, NotFoundError
from app.models.attempt import ExamAttempt, StudentAnswer
from app.models.enums import MANUAL_QUESTION_TYPES, AnswerStatus, AttemptStatus
from app.models.user import User
from app.repositories.attempt_repository import AttemptRepository
from app.repositories.exam_repository import ExamRepository
from app.services.attempt_service import AttemptService


class GradingService:
    def __init__(self, db: Session) -> None:
        self.db = db
        self.attempts = AttemptRepository(db)
        self.exams = ExamRepository(db)
        self.attempt_service = AttemptService(db)

    # --------------------------------------------------------- authorization

    def _exam_owned_by(self, exam_id: int, actor: User):
        exam = self.exams.get(exam_id)
        if exam is None:
            raise NotFoundError("Exam not found")
        if actor.is_admin or exam.teacher_id == actor.id:
            return exam
        raise NotFoundError("Exam not found")

    def _attempt_for_owner(self, attempt_id: int, actor: User) -> ExamAttempt:
        attempt = self.attempts.get(attempt_id)
        if attempt is None:
            raise NotFoundError("Attempt not found")
        self._exam_owned_by(attempt.exam_id, actor)
        return attempt

    # ------------------------------------------------------------- listing

    def queue_for_exam(self, exam_id: int, actor: User) -> list[dict[str, Any]]:
        """Submitted attempts, and how much marking each still needs."""
        self._exam_owned_by(exam_id, actor)
        rows: list[dict[str, Any]] = []
        for result in self.attempts.list_results_for_exam(exam_id):
            attempt = result.attempt
            profile = result.student.student_profile
            rows.append(
                {
                    "attempt_id": attempt.id,
                    "student_id": result.student.id,
                    "student_name": result.student.name,
                    "student_number": profile.student_id if profile else result.student.user_id,
                    "submitted_at": attempt.submitted_at,
                    "awaiting_marks": self.attempt_service.count_pending_manual(attempt),
                    "total_score": float(result.total_score),
                    "total_marks": result.exam.total_marks,
                }
            )
        return rows

    def answers_to_mark(self, attempt_id: int, actor: User) -> dict[str, Any]:
        """One student's written answers, beside the question they answered."""
        attempt = self._attempt_for_owner(attempt_id, actor)
        links = {link.id: link for link in self.exams.list_exam_questions(attempt.exam_id)}
        answers = {answer.exam_question_id: answer for answer in attempt.answers}

        items: list[dict[str, Any]] = []
        for position, link_id in enumerate(attempt.question_order, start=1):
            link = links.get(link_id)
            if link is None:  # pragma: no cover - frozen exam
                continue
            snapshot = link.question_snapshot or {}
            if snapshot.get("type") not in MANUAL_QUESTION_TYPES:
                continue
            answer = answers.get(link_id)
            items.append(
                {
                    "answer_id": answer.id if answer else None,
                    "exam_question_id": link.id,
                    "position": position,
                    "type": snapshot.get("type"),
                    "question_text": snapshot.get("question_text", ""),
                    "language": snapshot.get("language"),
                    "max_marks": link.marks_snapshot,
                    "answer_text": answer.answer_text if answer else None,
                    "answer_image_urls": list(answer.answer_image_urls or [])
                    if answer
                    else [],
                    "marks_awarded": (
                        float(answer.marks_awarded)
                        if answer and answer.marks_awarded is not None
                        else None
                    ),
                    "feedback": answer.feedback if answer else None,
                    "status": answer.status if answer else AnswerStatus.PENDING.value,
                }
            )

        return {
            "attempt_id": attempt.id,
            "exam_id": attempt.exam_id,
            "exam_title": attempt.exam.title,
            "student_name": attempt.student.name,
            "submitted_at": attempt.submitted_at,
            "awaiting_marks": self.attempt_service.count_pending_manual(attempt),
            "answers": items,
        }

    # ------------------------------------------------------------- marking

    def evaluate(
        self,
        attempt_id: int,
        answer_id: int,
        actor: User,
        *,
        marks_awarded: float,
        feedback: str | None,
    ) -> StudentAnswer:
        attempt = self._attempt_for_owner(attempt_id, actor)

        if attempt.status == AttemptStatus.ACTIVE:
            raise ConflictError(
                "This attempt is still in progress and cannot be marked yet",
                code="attempt_in_progress",
            )

        answer = next(
            (item for item in attempt.answers if item.id == answer_id), None
        )
        if answer is None:
            raise NotFoundError("That answer is not part of this attempt")

        link = self.exams.get_exam_question(attempt.exam_id, answer.exam_question_id)
        snapshot = (link.question_snapshot if link else None) or {}
        if snapshot.get("type") not in MANUAL_QUESTION_TYPES:
            raise InvalidRequestError(
                "That question was marked automatically and cannot be changed by hand",
                code="not_manually_graded",
            )

        maximum = link.marks_snapshot if link else 0
        if marks_awarded < 0 or marks_awarded > maximum:
            raise InvalidRequestError(
                f"Marks must be between 0 and {maximum} for this question",
                code="marks_out_of_range",
            )

        now = datetime.now(UTC)
        answer.marks_awarded = Decimal(str(marks_awarded))
        answer.feedback = (feedback or "").strip() or None
        answer.status = AnswerStatus.EVALUATED.value
        answer.evaluated_by = actor.id
        answer.evaluated_at = now

        # The total is rebuilt from the answers, never incremented, so re-marking the
        # same answer cannot drift the score.
        self.attempt_service.recompute_result(attempt, now=now)
        self.db.commit()
        return answer
