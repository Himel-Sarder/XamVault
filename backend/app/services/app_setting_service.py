from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.app_setting import AppSetting
from app.models.user import User
from app.schemas.app_setting import AppSettingUpdate

#: The one row, by primary key. See ``AppSetting``.
_ROW_ID = 1


class AppSettingService:
    """Reads and writes the single row of installation settings.

    The row is created on first read rather than by the migration, so a database that
    predates this feature -- or a fresh test database -- answers with the configured
    default instead of raising. ``UNIVERSITY_NAME`` in the environment stays the seed:
    it is what a brand new installation is called until somebody says otherwise.
    """

    def __init__(self, db: Session) -> None:
        self.db = db

    def _row(self) -> AppSetting | None:
        return self.db.execute(
            select(AppSetting).where(AppSetting.id == _ROW_ID)
        ).scalar_one_or_none()

    def get(self) -> AppSetting:
        row = self._row()
        if row is None:
            row = AppSetting(id=_ROW_ID, university_name=settings.UNIVERSITY_NAME)
            self.db.add(row)
            self.db.commit()
            self.db.refresh(row)
        return row

    def university_name(self) -> str:
        """The name alone, for the reports that print it.

        Read-only callers should not have to care that the row is created lazily, and a
        report must not fail because nobody has opened the settings screen yet.
        """
        row = self._row()
        return row.university_name if row else settings.UNIVERSITY_NAME

    def update(self, data: AppSettingUpdate, actor: User) -> AppSetting:
        row = self.get()
        row.university_name = data.university_name
        row.updated_by = actor.id
        self.db.commit()
        self.db.refresh(row)
        return row
