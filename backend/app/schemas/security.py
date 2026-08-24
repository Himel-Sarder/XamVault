from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field

SecurityEventLiteral = Literal[
    "APP_BACKGROUND",
    "APP_FOREGROUND",
    "SCREENSHOT_ATTEMPT",
    "SCREEN_RECORDING",
    "EXTERNAL_ACTIVITY",
    "NETWORK_DISCONNECT",
    "NETWORK_RECONNECT",
    "DEVICE_TIME_CHANGE",
    "EXAM_RESTART",
    "LOCKDOWN_ENGAGED",
    "LOCKDOWN_UNAVAILABLE",
]


class SecurityEventReport(BaseModel):
    """What the device says happened.

    Note what is absent: severity and a timestamp. The device reports *what*, the server
    decides *how serious* and records *when* — otherwise a patched client could file its
    own screenshot attempt as harmless, or backdate it.
    """

    event_type: SecurityEventLiteral
    metadata: dict[str, Any] | None = Field(
        default=None,
        description="Small, free-form context — e.g. how long the app was backgrounded.",
    )


class SecurityEventBatch(BaseModel):
    """Events queue up while the device is offline, so they arrive in batches (§39)."""

    events: list[SecurityEventReport] = Field(min_length=1, max_length=50)


class SecurityEventResponse(BaseModel):
    id: int
    attempt_id: int
    event_type: str
    severity: str
    occurred_at: datetime
    metadata: dict[str, Any] | None = None


class AttemptSecurityReport(BaseModel):
    """One student's event trail, for a teacher to interpret."""

    attempt_id: int
    student_name: str
    total_events: int
    warnings: int
    critical: int
    events: list[SecurityEventResponse]
