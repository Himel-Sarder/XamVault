from __future__ import annotations

from fastapi import APIRouter, status

from app.core.deps import DbSession, StudentUser, TeacherUser
from app.schemas.security import (
    AttemptSecurityReport,
    SecurityEventBatch,
    SecurityEventResponse,
)
from app.services.security_service import SecurityService

router = APIRouter(prefix="/attempts", tags=["security"])


@router.post(
    "/{attempt_id}/security-events",
    response_model=list[SecurityEventResponse],
    status_code=status.HTTP_201_CREATED,
    summary="Report what the device observed during an exam (student)",
)
def report_events(
    attempt_id: int, payload: SecurityEventBatch, current_user: StudentUser, db: DbSession
):
    """Accepts a batch, because events queue up while the device is offline.

    The device says *what* happened; the server decides how serious it is and when it was
    recorded. Nothing here ends an attempt or accuses anyone (§38).
    """
    recorded = SecurityService(db).record(
        attempt_id,
        current_user,
        [(event.event_type, event.metadata) for event in payload.events],
    )
    return [
        SecurityEventResponse(
            id=event.id,
            attempt_id=event.attempt_id,
            event_type=event.event_type,
            severity=event.severity,
            occurred_at=event.occurred_at,
            metadata=event.event_metadata,
        )
        for event in recorded
    ]


@router.get(
    "/{attempt_id}/security-events",
    response_model=AttemptSecurityReport,
    summary="The event trail for one attempt (exam owner)",
)
def read_events(attempt_id: int, current_user: TeacherUser, db: DbSession):
    return SecurityService(db).report_for_attempt(attempt_id, current_user)
