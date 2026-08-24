"""Phase 17 — how an exam and its questions actually performed (§45, §46).

Read-only, derived entirely from the attempts and their frozen question snapshots. The
figures are descriptive: they tell a teacher which questions were hard, not which
students to suspect.
"""

from __future__ import annotations

import statistics
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.orm import Session, selectinload

from app.core.exceptions import NotFoundError
from app.models.attempt import ExamAttempt
from app.models.enums import (
    CHOICE_QUESTION_TYPES,
    AnswerStatus,
    AttemptStatus,
    JoinRequestStatus,
)
from app.models.exam import Exam
from app.models.join_request import JoinRequest
from app.models.user import User
from app.repositories.attempt_repository import AttemptRepository
from app.repositories.exam_repository import ExamRepository
from app.schemas.analytics import (
    CohortCounts,
    DistributionBucket,
    ExamAnalytics,
    QuestionAnalytics,
    ScoreSummary,
)

# Five even bands. Coarse enough to read at a glance, fine enough to show a shape.
BUCKETS: tuple[tuple[int, int], ...] = ((0, 20), (21, 40), (41, 60), (61, 80), (81, 100))

FINISHED = {AttemptStatus.SUBMITTED.value, AttemptStatus.AUTO_SUBMITTED.value}


class AnalyticsService:
    def __init__(self, db: Session) -> None:
        self.db = db
        self.exams = ExamRepository(db)
        self.attempts = AttemptRepository(db)

    def for_exam(self, exam_id: int, actor: User, *, pass_percentage: float) -> ExamAnalytics:
        exam = self._owned_exam(exam_id, actor)
        attempts = self._attempts(exam_id)
        finished = [a for a in attempts if a.status in FINISHED]
        results = {r.attempt_id: r for r in self.attempts.list_results_for_exam(exam_id)}

        percentages = [float(results[a.id].percentage) for a in finished if a.id in results]
        approved = self._approved_count(exam_id)
        passed = sum(1 for p in percentages if p >= pass_percentage)

        return ExamAnalytics(
            exam_id=exam.id,
            exam_title=exam.title,
            course_code=exam.course.course_code,
            total_marks=exam.total_marks,
            cohort=CohortCounts(
                approved=approved,
                submitted=len(finished),
                in_progress=sum(1 for a in attempts if a.status == AttemptStatus.ACTIVE),
                # Never negative: clamp rather than show nonsense if the counts disagree.
                absent=max(0, approved - len(attempts)),
            ),
            scores=self._scores(percentages),
            pass_percentage=pass_percentage,
            passed=passed,
            failed=len(percentages) - passed,
            pass_rate=round(passed / len(percentages) * 100, 1) if percentages else None,
            distribution=self._distribution(percentages),
            questions=self._questions(exam, finished),
        )

    # ---------------------------------------------------------------- pieces

    def _owned_exam(self, exam_id: int, actor: User) -> Exam:
        exam = self.exams.get(exam_id)
        if exam is None:
            raise NotFoundError("Exam not found")
        if actor.is_admin or exam.teacher_id == actor.id:
            return exam
        raise NotFoundError("Exam not found")

    def _attempts(self, exam_id: int) -> list[ExamAttempt]:
        return list(
            self.db.execute(
                select(ExamAttempt)
                .where(ExamAttempt.exam_id == exam_id)
                .options(selectinload(ExamAttempt.answers))
            )
            .scalars()
            .all()
        )

    def _approved_count(self, exam_id: int) -> int:
        return self.db.execute(
            select(func.count())
            .select_from(JoinRequest)
            .where(
                JoinRequest.exam_id == exam_id,
                JoinRequest.status == JoinRequestStatus.APPROVED.value,
            )
        ).scalar_one()

    @staticmethod
    def _scores(percentages: list[float]) -> ScoreSummary:
        if not percentages:
            # An average of nothing is not zero: showing 0% would read as "everyone
            # failed" rather than "nobody has sat it".
            return ScoreSummary(average=None, highest=None, lowest=None, median=None)
        return ScoreSummary(
            average=round(statistics.fmean(percentages), 1),
            highest=round(max(percentages), 1),
            lowest=round(min(percentages), 1),
            median=round(statistics.median(percentages), 1),
        )

    @staticmethod
    def _distribution(percentages: list[float]) -> list[DistributionBucket]:
        return [
            DistributionBucket(
                label=f"{low}-{high}%",
                from_percent=low,
                to_percent=high,
                count=sum(1 for p in percentages if low <= p <= high),
            )
            for low, high in BUCKETS
        ]

    def _questions(self, exam: Exam, finished: list[ExamAttempt]) -> list[QuestionAnalytics]:
        links = self.exams.list_exam_questions(exam.id)
        by_question: dict[int, list[Any]] = {link.id: [] for link in links}
        for attempt in finished:
            for answer in attempt.answers:
                if answer.exam_question_id in by_question:
                    by_question[answer.exam_question_id].append(answer)

        sat = len(finished)
        analytics: list[QuestionAnalytics] = []
        for position, link in enumerate(links, start=1):
            snapshot = link.question_snapshot or {}
            kind = str(snapshot.get("type", ""))
            answers = by_question[link.id]
            answered = sum(1 for a in answers if a.is_answered)

            entry = QuestionAnalytics(
                exam_question_id=link.id,
                position=position,
                type=kind,
                question_text=snapshot.get("question_text", ""),
                marks=link.marks_snapshot,
                is_auto_marked=kind in CHOICE_QUESTION_TYPES,
                answered=answered,
                # Everyone who sat the paper but left this one blank.
                skipped=max(0, sat - answered),
            )

            if kind in CHOICE_QUESTION_TYPES:
                correct_ids = {
                    option["id"]
                    for option in snapshot.get("options", [])
                    if option.get("is_correct")
                }
                correct = sum(1 for a in answers if a.selected_option_id in correct_ids)
                entry.correct = correct
                entry.wrong = max(0, answered - correct)
                entry.correct_rate = round(correct / sat * 100, 1) if sat else None
            else:
                marked = [float(a.marks_awarded) for a in answers if a.marks_awarded is not None]
                entry.average_marks = round(statistics.fmean(marked), 2) if marked else None
                entry.awaiting_marks = sum(
                    1 for a in answers if a.status == AnswerStatus.PENDING
                )

            analytics.append(entry)
        return analytics
