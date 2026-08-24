from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response, status

from app.core.deps import DbSession, TeacherUser
from app.schemas.common import Page, PageParams
from app.schemas.question import QuestionCreate
from app.schemas.question_bank import BankQuestionResponse, BankTopicsResponse
from app.services.question_bank_service import QuestionBankService

router = APIRouter(prefix="/question-bank", tags=["question-bank"])


# Declared before /{question_id} so "topics" is never parsed as an id.
@router.get("/topics", response_model=BankTopicsResponse, summary="Topics I have used")
def list_topics(current_user: TeacherUser, db: DbSession):
    return BankTopicsResponse(topics=QuestionBankService(db).topics(current_user))


@router.get(
    "",
    response_model=Page[BankQuestionResponse],
    summary="My reusable questions",
)
def list_questions(
    current_user: TeacherUser,
    db: DbSession,
    page: Annotated[PageParams, Depends()],
    question_type: Annotated[
        str | None, Query(alias="type", description="TEXT_MCQ, SHORT_ANSWER, ...")
    ] = None,
    difficulty: Annotated[str | None, Query(description="easy, medium, hard")] = None,
    topic: Annotated[str | None, Query(description="Exact topic match")] = None,
    search: Annotated[str | None, Query(description="Match the question text")] = None,
):
    items, total = QuestionBankService(db).list_questions(
        current_user,
        question_type=question_type,
        difficulty=difficulty,
        topic=topic,
        search=search,
        offset=page.offset,
        limit=page.page_size,
    )
    return Page[BankQuestionResponse](
        items=items, total=total, page=page.page, page_size=page.page_size
    )


@router.post(
    "",
    response_model=BankQuestionResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Add a question to my library, without attaching it to an exam",
)
def create_question(payload: QuestionCreate, current_user: TeacherUser, db: DbSession):
    return QuestionBankService(db).create(payload, current_user)


@router.get(
    "/{question_id}",
    response_model=BankQuestionResponse,
    summary="One of my questions",
)
def read_question(question_id: int, current_user: TeacherUser, db: DbSession):
    return QuestionBankService(db).get(question_id, current_user)


@router.put(
    "/{question_id}",
    response_model=BankQuestionResponse,
    summary="Edit one of my questions",
)
def update_question(
    question_id: int, payload: QuestionCreate, current_user: TeacherUser, db: DbSession
):
    """Draft exams using this question follow the edit; published ones do not — they
    render from the snapshot frozen when they were published."""
    return QuestionBankService(db).update(question_id, payload, current_user)


@router.delete(
    "/{question_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a question no exam uses",
)
def delete_question(question_id: int, current_user: TeacherUser, db: DbSession) -> Response:
    QuestionBankService(db).delete(question_id, current_user)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
