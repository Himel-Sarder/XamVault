from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.models.types import UTCDateTime, utcnow

if TYPE_CHECKING:
    from app.models.course import Course
    from app.models.user import User


class Department(Base):
    __tablename__ = "departments"

    id: Mapped[int] = mapped_column(primary_key=True)
    code: Mapped[str] = mapped_column(String(20), unique=True, nullable=False)
    name: Mapped[str] = mapped_column(String(150), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utcnow, server_default=func.now()
    )

    users: Mapped[list["User"]] = relationship(back_populates="department")
    courses: Mapped[list["Course"]] = relationship(back_populates="department")

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return f"<Department {self.code}>"
