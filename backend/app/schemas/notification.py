from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel

from app.schemas.common import ORMModel

NotificationCategoryLiteral = Literal[
    "exam_published",
    "join_request_received",
    "join_request_approved",
    "join_request_rejected",
    "exam_submitted",
    "result_published",
]


class NotificationResponse(ORMModel):
    id: int
    category: NotificationCategoryLiteral
    title: str
    body: str
    is_read: bool

    # A pointer for the app to navigate with — an exam id, a result id — not a copy of
    # the record it refers to.
    payload: dict[str, Any] | None
    created_at: datetime
    read_at: datetime | None


class UnreadCountResponse(BaseModel):
    unread: int


class MarkReadResponse(BaseModel):
    updated: int
