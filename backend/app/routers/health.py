from __future__ import annotations

from fastapi import APIRouter, Response, status
from sqlalchemy import text

from app.core.config import settings
from app.core.deps import DbSession

router = APIRouter(tags=["health"])


@router.get("/health", summary="Liveness and database readiness")
def health(db: DbSession, response: Response) -> dict[str, str]:
    """Render polls this. It reports 503 when the database is unreachable so a broken
    instance is taken out of rotation instead of accepting traffic it cannot serve."""
    database = "ok"
    try:
        db.execute(text("SELECT 1"))
    except Exception:  # noqa: BLE001 - the reason belongs in logs, not in the response
        database = "unavailable"
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    return {"status": "ok" if database == "ok" else "degraded",
            "database": database,
            "version": settings.VERSION}
