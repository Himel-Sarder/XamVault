from __future__ import annotations

from fastapi import APIRouter

from app.core.deps import AdminUser, CurrentUser, DbSession
from app.schemas.app_setting import AppSettingResponse, AppSettingUpdate
from app.services.app_setting_service import AppSettingService

router = APIRouter(prefix="/settings", tags=["settings"])


@router.get("", response_model=AppSettingResponse, summary="Read installation settings")
def read_settings(_: CurrentUser, db: DbSession) -> object:
    """Readable by anyone signed in: the name is printed on every report they can
    already download, so it is not the sort of thing worth an admin-only door."""
    return AppSettingService(db).get()


@router.put(
    "",
    response_model=AppSettingResponse,
    summary="Set the university name (admin)",
)
def update_settings(
    payload: AppSettingUpdate, current_user: AdminUser, db: DbSession
) -> object:
    return AppSettingService(db).update(payload, current_user)
