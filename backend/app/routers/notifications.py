from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response, status

from app.core.deps import CurrentUser, DbSession
from app.schemas.common import Page, PageParams
from app.schemas.notification import (
    MarkReadResponse,
    NotificationResponse,
    UnreadCountResponse,
)
from app.services.notification_service import NotificationService

router = APIRouter(prefix="/notifications", tags=["notifications"])


# Declared before /{notification_id} so "unread-count" is not parsed as an id.
@router.get(
    "/unread-count",
    response_model=UnreadCountResponse,
    summary="How many of my notifications are unread",
)
def unread_count(current_user: CurrentUser, db: DbSession):
    """Cheap enough to poll for a badge: one indexed COUNT, no rows returned."""
    return UnreadCountResponse(unread=NotificationService(db).unread_count(current_user))


@router.post(
    "/read-all",
    response_model=MarkReadResponse,
    summary="Mark all my notifications read",
)
def mark_all_read(current_user: CurrentUser, db: DbSession):
    return MarkReadResponse(updated=NotificationService(db).mark_all_read(current_user))


@router.get(
    "",
    response_model=Page[NotificationResponse],
    summary="My notifications, newest first",
)
def list_notifications(
    current_user: CurrentUser,
    db: DbSession,
    page: Annotated[PageParams, Depends()],
    unread_only: Annotated[bool, Query(description="Hide what I have already seen")] = False,
):
    """Scoped to the caller inside the query — there is no way to ask for anyone else's."""
    items, total = NotificationService(db).list_for(
        current_user, unread_only=unread_only, offset=page.offset, limit=page.page_size
    )
    return Page[NotificationResponse](
        items=[NotificationResponse.model_validate(item) for item in items],
        total=total,
        page=page.page,
        page_size=page.page_size,
    )


@router.delete(
    "/read",
    summary="Clear the notifications I have already read",
)
def clear_read(current_user: CurrentUser, db: DbSession) -> dict[str, int]:
    """Declared before /{notification_id} so "read" is never parsed as an id.

    Unread notifications are left alone: clearing should not be able to remove
    something the reader has not seen yet.
    """
    return {"cleared": NotificationService(db).clear_read(current_user)}


@router.delete(
    "/{notification_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Remove one notification from my inbox",
)
def delete_notification(
    notification_id: int, current_user: CurrentUser, db: DbSession
) -> Response:
    NotificationService(db).delete(notification_id, current_user)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/{notification_id}/read",
    response_model=NotificationResponse,
    summary="Mark one notification read",
)
def mark_read(notification_id: int, current_user: CurrentUser, db: DbSession):
    return NotificationService(db).mark_read(notification_id, current_user)
