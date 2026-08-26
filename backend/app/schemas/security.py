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
    "DEVELOPER_MODE",
    "USB_DEBUGGING",
    "SPLIT_SCREEN",
    "EXTERNAL_DISPLAY",
    "OVERLAY_DETECTED",
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


class StudentSecuritySummary(BaseModel):
    """One student's activity during an exam, condensed to what a teacher scans for."""

    attempt_id: int
    student_id: int
    student_name: str
    student_number: str | None = None

    #: How many times the app left the foreground. The number a teacher actually asks for.
    exits: int
    #: Seconds spent outside the app, summed over every return.
    #:
    #: Counted from the *return*, because that is the only moment the elapsed time is
    #: known. An exit with no matching return therefore adds nothing here -- see
    #: ``unreturned_exits``, which is what stops that silence being read as zero.
    seconds_away: int
    longest_away_seconds: int
    #: Exits the app never came back from: the student submitted from elsewhere, the
    #: attempt expired, or the device died mid-exam.
    unreturned_exits: int

    screenshot_attempts: int
    screen_recordings: int
    time_changes: int
    restarts: int

    total_events: int
    warnings: int
    critical: int

    #: What lockdown the device actually granted, verbatim from the trail. An exam sat
    #: without protection is a fact the invigilator needs before reading any of the rest.
    lockdown: str | None = None


class ExamSecuritySummary(BaseModel):
    """Every student who sat one exam, most activity first.

    Ordering is deliberate: a teacher opening this wants the outliers, not an
    alphabetical list they have to read all of.
    """

    exam_id: int
    exam_title: str
    students: list[StudentSecuritySummary]
