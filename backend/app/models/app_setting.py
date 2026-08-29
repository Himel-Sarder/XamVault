from __future__ import annotations

from datetime import datetime

from sqlalchemy import CheckConstraint, ForeignKey, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.models.types import UTCDateTime, utcnow


class AppSetting(Base):
    """The handful of things about *this* installation an administrator sets.

    One row, forced by a check constraint on the primary key. A settings table that can
    hold two rows eventually holds two rows, and then no caller agrees on which one is
    the truth; making that impossible at the database is cheaper than the convention
    everyone has to remember.
    """

    __tablename__ = "app_settings"
    __table_args__ = (CheckConstraint("id = 1", name="single_row"),)

    #: Always 1. See the class docstring.
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=False)

    #: Printed at the top of every report and shown on the sign-in screen.
    university_name: Mapped[str] = mapped_column(String(150), nullable=False)

    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime,
        nullable=False,
        default=utcnow,
        onupdate=utcnow,
        server_default=func.now(),
    )
    #: Who last changed it. Kept as SET NULL so removing an administrator does not
    #: take the institution's name with them.
    updated_by: Mapped[int | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return f"<AppSetting {self.university_name}>"
