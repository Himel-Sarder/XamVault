from __future__ import annotations

from fastapi import APIRouter

from app.core.deps import DbSession, StudentUser, TeacherUser
from app.schemas.result import StudentResultResponse
from app.services.result_service import ResultService

router = APIRouter(prefix="/results", tags=["results"])


@router.get(
    "",
    response_model=list[StudentResultResponse],
    summary="My published results (student)",
)
def list_my_results(current_user: StudentUser, db: DbSession):
    return ResultService(db).list_mine(current_user)


@router.get(
    "/{result_id}",
    response_model=StudentResultResponse,
    summary="One of my published results (student)",
)
def read_my_result(result_id: int, current_user: StudentUser, db: DbSession):
    return ResultService(db).get_mine(result_id, current_user)
