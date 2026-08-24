from __future__ import annotations

from fastapi import APIRouter

from app.core.deps import DbSession, TeacherUser
from app.schemas.grading import (
    AttemptGradingResponse,
    EvaluateAnswerRequest,
    EvaluatedAnswerResponse,
)
from app.services.grading_service import GradingService

router = APIRouter(prefix="/attempts", tags=["grading"])


@router.get(
    "/{attempt_id}/grading",
    response_model=AttemptGradingResponse,
    summary="Written answers awaiting a mark (exam owner)",
)
def answers_to_mark(attempt_id: int, current_user: TeacherUser, db: DbSession):
    return GradingService(db).answers_to_mark(attempt_id, current_user)


@router.post(
    "/{attempt_id}/answers/{answer_id}/evaluate",
    response_model=EvaluatedAnswerResponse,
    summary="Award marks for one written answer (exam owner)",
)
def evaluate_answer(
    attempt_id: int,
    answer_id: int,
    payload: EvaluateAnswerRequest,
    current_user: TeacherUser,
    db: DbSession,
):
    service = GradingService(db)
    answer = service.evaluate(
        attempt_id,
        answer_id,
        current_user,
        marks_awarded=payload.marks_awarded,
        feedback=payload.feedback,
    )
    attempt = service.attempts.get(attempt_id)
    result = service.attempts.get_result_for_attempt(attempt_id)
    return EvaluatedAnswerResponse(
        answer_id=answer.id,
        exam_question_id=answer.exam_question_id,
        marks_awarded=float(answer.marks_awarded or 0),
        feedback=answer.feedback,
        status=answer.status,
        awaiting_marks=service.attempt_service.count_pending_manual(attempt),
        total_score=float(result.total_score) if result else 0.0,
    )
