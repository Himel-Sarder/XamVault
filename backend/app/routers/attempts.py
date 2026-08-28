from __future__ import annotations

from datetime import UTC, datetime
from typing import Annotated

from fastapi import APIRouter, File, Query, UploadFile, status

from app.core.deps import DbSession, StudentUser
from app.models.attempt import ExamAttempt, StudentAnswer
from app.schemas.attempt import AnswerAck, AnswerSubmit, AttemptResponse, SubmitResponse
from app.services.attempt_service import AttemptService

router = APIRouter(prefix="/attempts", tags=["attempts"])


def _ack(
    exam_question_id: int, attempt: ExamAttempt, answer: StudentAnswer
) -> AnswerAck:
    """The same small acknowledgement for every way of answering."""
    return AnswerAck(
        exam_question_id=exam_question_id,
        selected_option_id=answer.selected_option_id,
        answer_text=answer.answer_text,
        answer_image_urls=list(answer.answer_image_urls or []),
        answered_count=sum(1 for item in attempt.answers if item.is_answered),
        # Every save re-syncs the client's countdown against the server's.
        remaining_seconds=attempt.remaining_seconds(datetime.now(UTC)),
    )


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
    attempt, answer = AttemptService(db).save_answer(
        attempt_id,
        current_user,
        exam_question_id=payload.exam_question_id,
        selected_option_id=payload.selected_option_id,
        answer_text=payload.answer_text,
    )
    return _ack(payload.exam_question_id, attempt, answer)


@router.post(
    "/{attempt_id}/answers/{exam_question_id}/photos",
    response_model=AnswerAck,
    status_code=status.HTTP_201_CREATED,
    summary="Add a photograph of work done on paper (student)",
)
async def add_answer_photo(
    attempt_id: int,
    exam_question_id: int,
    current_user: StudentUser,
    db: DbSession,
    file: UploadFile = File(...),
):
    """Uploading is answering, so it is gated exactly as answering is: your own attempt,
    still open, and still inside the time.

    The three-photograph cap is enforced here rather than only on the button, because a
    cap that lives in the UI is a suggestion.
    """
    attempt, answer = await AttemptService(db).add_photo(
        attempt_id, current_user, exam_question_id=exam_question_id, upload=file
    )
    return _ack(exam_question_id, attempt, answer)


@router.delete(
    "/{attempt_id}/answers/{exam_question_id}/photos",
    response_model=AnswerAck,
    summary="Remove one photograph from an answer (student)",
)
def remove_answer_photo(
    attempt_id: int,
    exam_question_id: int,
    url: Annotated[
        str, Query(description="The photograph's URL, as returned when it was added")
    ],
    current_user: StudentUser,
    db: DbSession,
):
    """Taken by URL rather than by index: a list position is ambiguous the moment two
    removals race, and the URL names exactly the photograph the student tapped."""
    attempt, answer = AttemptService(db).remove_photo(
        attempt_id, current_user, exam_question_id=exam_question_id, url=url
    )
    return _ack(exam_question_id, attempt, answer)


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
