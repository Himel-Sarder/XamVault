"""Phase 12 — the record of what a device reported during an exam (§39).

Nothing here punishes a student. Events are recorded with the *server's* clock and the
server's own severity, and surfaced to the teacher; the platform draws no conclusion from
them and never ends an attempt because of one.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.orm import Session, selectinload

from app.core.exceptions import ConflictError, NotFoundError
from app.models.attempt import ExamAttempt
from app.models.enums import (
    DEFAULT_EVENT_SEVERITY,
    SecurityEventType,
    SecuritySeverity,
)
from app.models.security_event import SecurityEvent
from app.models.user import User
from app.repositories.attempt_repository import AttemptRepository
from app.repositories.exam_repository import ExamRepository

# A misbehaving client must not be able to fill the table.
MAX_EVENTS_PER_ATTEMPT = 500


class SecurityService:
    def __init__(self, db: Session) -> None:
        self.db = db
        self.attempts = AttemptRepository(db)
        self.exams = ExamRepository(db)

    # ------------------------------------------------------------- reporting

    def record(
        self, attempt_id: int, student: User, events: list[tuple[str, dict[str, Any] | None]]
    ) -> list[SecurityEvent]:
        attempt = self.attempts.get(attempt_id)
        if attempt is None or attempt.student_id != student.id:
            raise NotFoundError("Attempt not found")

        # Reports are only meaningful while the exam is being sat. Accepting them
        # afterwards would let a client write history into a finished attempt.
        if not attempt.is_active:
            raise ConflictError(
                "This attempt is no longer running", code="attempt_closed"
            )

        existing = self.db.execute(
            select(func.count())
            .select_from(SecurityEvent)
            .where(SecurityEvent.attempt_id == attempt.id)
        ).scalar_one()
        room = MAX_EVENTS_PER_ATTEMPT - existing
        if room <= 0:
            raise ConflictError(
                "Too many security events recorded for this attempt",
                code="event_limit_reached",
            )

        now = datetime.now(UTC)
        recorded: list[SecurityEvent] = []
        for event_type, metadata in events[:room]:
            event = SecurityEvent(
                attempt_id=attempt.id,
                student_id=student.id,
                event_type=event_type,
                # Severity is the server's judgement, not the device's claim.
                severity=DEFAULT_EVENT_SEVERITY.get(
                    event_type, SecuritySeverity.INFO.value
                ),
                occurred_at=now,
                event_metadata=metadata,
            )
            self.db.add(event)
            recorded.append(event)

        self.db.commit()
        return recorded

    # --------------------------------------------------------------- reading

    def report_for_attempt(self, attempt_id: int, actor: User) -> dict[str, Any]:
        attempt = self.attempts.get(attempt_id)
        if attempt is None:
            raise NotFoundError("Attempt not found")
        self._assert_owns_exam(attempt, actor)

        events = list(
            self.db.execute(
                select(SecurityEvent)
                .where(SecurityEvent.attempt_id == attempt.id)
                .order_by(SecurityEvent.occurred_at, SecurityEvent.id)
            )
            .scalars()
            .all()
        )
        return {
            "attempt_id": attempt.id,
            "student_name": attempt.student.name,
            "total_events": len(events),
            "warnings": sum(1 for e in events if e.severity == SecuritySeverity.WARNING),
            "critical": sum(1 for e in events if e.severity == SecuritySeverity.CRITICAL),
            "events": [
                {
                    "id": event.id,
                    "attempt_id": event.attempt_id,
                    "event_type": event.event_type,
                    "severity": event.severity,
                    "occurred_at": event.occurred_at,
                    "metadata": event.event_metadata,
                }
                for event in events
            ],
        }

    def summary_for_exam(self, exam_id: int, actor: User) -> dict[str, Any]:
        """Every student who sat this exam, with their activity condensed to a row.

        The per-attempt trail answers "what did this student do"; this answers "who
        should I look at first", which is the question a teacher actually opens with.
        """
        exam = self.exams.get(exam_id)
        if exam is None or not (actor.is_admin or exam.teacher_id == actor.id):
            # 404 rather than 403: whether exam 42 exists is not this caller's business.
            raise NotFoundError("Exam not found")

        attempts = list(
            self.db.execute(
                select(ExamAttempt)
                .where(ExamAttempt.exam_id == exam_id)
                .options(selectinload(ExamAttempt.student))
                .order_by(ExamAttempt.id)
            )
            .scalars()
            .all()
        )
        if not attempts:
            return {"exam_id": exam.id, "exam_title": exam.title, "students": []}

        by_attempt: dict[int, list[SecurityEvent]] = {a.id: [] for a in attempts}
        events = (
            self.db.execute(
                select(SecurityEvent)
                .where(SecurityEvent.attempt_id.in_(list(by_attempt)))
                .order_by(SecurityEvent.occurred_at, SecurityEvent.id)
            )
            .scalars()
            .all()
        )
        for event in events:
            by_attempt[event.attempt_id].append(event)

        rows = [
            self._summarise(attempt, by_attempt.get(attempt.id, []))
            for attempt in attempts
        ]
        # Busiest first. Critical outranks warnings, which outrank a long absence, so
        # the student who needs a human decision is at the top rather than in the middle.
        rows.sort(
            key=lambda r: (r["critical"], r["warnings"], r["exits"], r["seconds_away"]),
            reverse=True,
        )
        return {"exam_id": exam.id, "exam_title": exam.title, "students": rows}

    @staticmethod
    def _summarise(attempt: ExamAttempt, events: list[SecurityEvent]) -> dict[str, Any]:
        def count(kind: SecurityEventType) -> int:
            return sum(1 for e in events if e.event_type == kind.value)

        returns = [e for e in events if e.event_type == SecurityEventType.APP_FOREGROUND.value]
        away_ms: list[int] = []
        for event in returns:
            value = (event.event_metadata or {}).get("away_ms")
            if isinstance(value, (int, float)) and value >= 0:
                away_ms.append(int(value))

        exits = count(SecurityEventType.APP_BACKGROUND)
        lockdown = next(
            (
                (e.event_metadata or {}).get("detail")
                for e in events
                if e.event_type
                in (
                    SecurityEventType.LOCKDOWN_ENGAGED.value,
                    SecurityEventType.LOCKDOWN_UNAVAILABLE.value,
                )
            ),
            None,
        )
        profile = attempt.student.student_profile

        return {
            "attempt_id": attempt.id,
            "student_id": attempt.student_id,
            "student_name": attempt.student.name,
            "student_number": profile.student_id if profile else None,
            "exits": exits,
            "seconds_away": sum(away_ms) // 1000,
            "longest_away_seconds": (max(away_ms) // 1000) if away_ms else 0,
            # An exit whose return was never reported contributes no duration, so it is
            # counted separately rather than silently averaged away.
            "unreturned_exits": max(0, exits - len(returns)),
            "screenshot_attempts": count(SecurityEventType.SCREENSHOT_ATTEMPT),
            "screen_recordings": count(SecurityEventType.SCREEN_RECORDING),
            "time_changes": count(SecurityEventType.DEVICE_TIME_CHANGE),
            "restarts": count(SecurityEventType.EXAM_RESTART),
            "total_events": len(events),
            "warnings": sum(1 for e in events if e.severity == SecuritySeverity.WARNING),
            "critical": sum(1 for e in events if e.severity == SecuritySeverity.CRITICAL),
            "lockdown": lockdown,
        }

    def _assert_owns_exam(self, attempt: ExamAttempt, actor: User) -> None:
        exam = self.exams.get(attempt.exam_id)
        if exam is None:  # pragma: no cover - FK makes this unreachable
            raise NotFoundError("Attempt not found")
        if actor.is_admin or exam.teacher_id == actor.id:
            return
        raise NotFoundError("Attempt not found")
