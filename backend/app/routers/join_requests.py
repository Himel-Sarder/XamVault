from __future__ import annotations

from fastapi import APIRouter

from app.core.deps import DbSession, StudentUser, TeacherUser
from app.routers.exams import _join_request_response
from app.schemas.join_request import JoinRequestResponse, StudentJoinRequestResponse
from app.services.join_request_service import JoinRequestService

router = APIRouter(prefix="/join-requests", tags=["join-requests"])


# Declared before /{request_id}/... so "mine" is never parsed as an id.
@router.get(
    "/mine",
    response_model=list[StudentJoinRequestResponse],
    summary="My requests (student)",
)
def list_my_requests(current_user: StudentUser, db: DbSession):
    return JoinRequestService(db).list_mine(current_user)


@router.post(
    "/{request_id}/approve",
    response_model=JoinRequestResponse,
    summary="Approve one request (exam owner)",
)
def approve(request_id: int, current_user: TeacherUser, db: DbSession):
    request = JoinRequestService(db).review(request_id, current_user, approve=True)
    return _join_request_response(request)


@router.post(
    "/{request_id}/reject",
    response_model=JoinRequestResponse,
    summary="Reject one request (exam owner)",
)
def reject(request_id: int, current_user: TeacherUser, db: DbSession):
    request = JoinRequestService(db).review(request_id, current_user, approve=False)
    return _join_request_response(request)
