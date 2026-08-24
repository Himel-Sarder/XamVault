from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING, Any

from sqlalchemy import Boolean, CheckConstraint, ForeignKey, Index, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.models.enums import NOTIFICATION_CATEGORY_CHECK_SQL
from app.models.types import JSONColumn, UTCDateTime, utcnow

if TYPE_CHECKING:
    from app.models.user import User


class Notification(Base):
    """Something that happened, addressed to one person (§61).

    Stored server-side rather than pushed and forgotten: a student who had the app closed
    when their exam was published must still see it when they open it. Push delivery, when
    it exists, is a *second* channel for the same row — never the only one.
    """

    __tablename__ = "notifications"
    __table_args__ = (
        CheckConstraint(NOTIFICATION_CATEGORY_CHECK_SQL, name="category"),
        # The list is always "mine, newest first", usually filtered to unread.
        Index("ix_notifications_user_created", "user_id", "created_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    category: Mapped[str] = mapped_column(String(40), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    is_read: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, index=True)

    # Enough for the app to navigate somewhere useful when tapped — an exam id, a result
    # id. Deliberately small: this is a pointer, not a copy of the record.
    payload: Mapped[dict[str, Any] | None] = mapped_column(JSONColumn, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utcnow, server_default=func.now()
    )
    read_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)

    user: Mapped["User"] = relationship()

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return f"<Notification {self.category} user={self.user_id}>"
