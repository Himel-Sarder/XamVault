from __future__ import annotations

from datetime import UTC, datetime

from fastapi import APIRouter, status

from app.core.deps import DbSession, StudentUser
from app.schemas.attempt import AnswerAck, AnswerSubmit, AttemptResponse, SubmitResponse
from app.services.attempt_service import AttemptService

router = APIRouter(prefix="/attempts", tags=["attempts"])


@router.get(
    "/{attempt_id}",
    response_model=AttemptResponse,
    summary="Load or restore an attempt in progress",
)
def read_attempt(attempt_id: int, current_user: StudentUser, db: DbSession):
    """Everything needed to rebuild the exam screen after a crash, a restart or a
    reconnect (§60) — including the authoritative remaining time."""
    service = AttemptService(db)
    attempt = service.get(attempt_id, current_user)
    return service.build_view(attempt)


@router.post(
    "/{attempt_id}/answers",
    response_model=AnswerAck,
    summary="Save one answer",
)
def save_answer(
    attempt_id: int, payload: AnswerSubmit, current_user: StudentUser, db: DbSession
):
    service = AttemptService(db)
    attempt, answer = service.save_answer(
        attempt_id,
        current_user,
        exam_question_id=payload.exam_question_id,
        selected_option_id=payload.selected_option_id,
        answer_text=payload.answer_text,
    )
    return AnswerAck(
        exam_question_id=payload.exam_question_id,
        selected_option_id=answer.selected_option_id,
        answer_text=answer.answer_text,
        answered_count=sum(1 for item in attempt.answers if item.is_answered),
        # Every save re-syncs the client's countdown against the server's.
        remaining_seconds=attempt.remaining_seconds(datetime.now(UTC)),
    )


@router.post(
    "/{attempt_id}/submit",
    response_model=SubmitResponse,
    status_code=status.HTTP_200_OK,
    summary="Submit an attempt (freezes and grades it)",
)
def submit_attempt(attempt_id: int, current_user: StudentUser, db: DbSession):
    service = AttemptService(db)
    attempt = service.submit(attempt_id, current_user)
    result = service.attempts.get_result_for_attempt(attempt.id)
    return SubmitResponse(
        attempt_id=attempt.id,
        status=attempt.status,
        submitted_at=attempt.submitted_at,
        answered_count=sum(1 for item in attempt.answers if item.is_answered),
        total_questions=len(attempt.question_order),
        # Only handed back when the exam is set to reveal results immediately.
        result_id=result.id if result and result.is_published else None,
    )
