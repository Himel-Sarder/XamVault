from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response, status

from app.core.deps import AdminUser, CurrentUser, DbSession
from app.schemas.common import Page, PageParams
from app.schemas.user import UserCreate, UserDetailResponse, UserResponse, UserUpdate
from app.services.user_service import UserService

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me", response_model=UserDetailResponse, summary="Own profile")
def read_own_profile(current_user: CurrentUser, db: DbSession) -> object:
    return UserService(db).get_detail(current_user.id)


@router.get("", response_model=Page[UserResponse], summary="List users (admin)")
def list_users(
    _: AdminUser,
    db: DbSession,
    page: Annotated[PageParams, Depends()],
    role: Annotated[str | None, Query(description="Filter by role")] = None,
    search: Annotated[str | None, Query(description="Match name or user ID")] = None,
) -> Page[UserResponse]:
    users, total = UserService(db).list_users(
        role=role, search=search, offset=page.offset, limit=page.page_size
    )
    return Page[UserResponse](
        items=[UserResponse.model_validate(user) for user in users],
        total=total,
        page=page.page,
        page_size=page.page_size,
    )


@router.post(
    "",
    response_model=UserDetailResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a user (admin)",
)
def create_user(payload: UserCreate, _: AdminUser, db: DbSession) -> object:
    return UserService(db).create_user(payload)


@router.get("/{user_id}", response_model=UserDetailResponse, summary="Read a user (admin)")
def read_user(user_id: int, _: AdminUser, db: DbSession) -> object:
    return UserService(db).get_detail(user_id)


@router.get(
    "/{user_id}/deletion-impact",
    summary="What deleting this account would destroy (admin)",
)
def read_deletion_impact(user_id: int, _: AdminUser, db: DbSession) -> dict[str, int]:
    """Read before the confirmation, so the numbers can be shown rather than discovered."""
    return UserService(db).deletion_impact(user_id)


@router.delete(
    "/{user_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a deactivated account and everything it owns (admin)",
)
def delete_user(user_id: int, current_user: AdminUser, db: DbSession) -> Response:
    UserService(db).delete_user(user_id, current_user)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.patch("/{user_id}", response_model=UserDetailResponse, summary="Update a user (admin)")
def update_user(user_id: int, payload: UserUpdate, _: AdminUser, db: DbSession) -> object:
    return UserService(db).update_user(user_id, payload)
