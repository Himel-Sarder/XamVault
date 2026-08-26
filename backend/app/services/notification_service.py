"""Phase 19 — in-app notifications (§61).

Notifications are **stored**, not merely pushed. A student whose app was closed when
their exam was published must still see it when they open it, so the database row is the
notification and any push is a second channel for the same row.

Creating a notification never fails the action that caused it: being told about an
approval matters less than the approval itself, so a delivery problem must not roll one
back.
"""

from __future__ import annotations

import logging
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import delete, func, select, update
from sqlalchemy.orm import Session

from app.core.exceptions import NotFoundError
from app.models.course import CourseEnrollment
from app.models.enums import NotificationCategory
from app.models.exam import Exam
from app.models.notification import Notification
from app.models.user import User

logger = logging.getLogger("uniexam.notifications")


class NotificationService:
    def __init__(self, db: Session) -> None:
        self.db = db

    # ----------------------------------------------------------------- reads

    def list_for(
        self, user: User, *, unread_only: bool, offset: int, limit: int
    ) -> tuple[list[Notification], int]:
        base = select(Notification).where(Notification.user_id == user.id)
        if unread_only:
            base = base.where(Notification.is_read.is_(False))

        total = self.db.execute(
            select(func.count()).select_from(base.subquery())
        ).scalar_one()
        rows = (
            self.db.execute(
                base.order_by(Notification.created_at.desc(), Notification.id.desc())
                .offset(offset)
                .limit(limit)
            )
            .scalars()
            .all()
        )
        return list(rows), total

    def unread_count(self, user: User) -> int:
        return self.db.execute(
            select(func.count())
            .select_from(Notification)
            .where(Notification.user_id == user.id, Notification.is_read.is_(False))
        ).scalar_one()

    # ---------------------------------------------------------------- writes

    def mark_read(self, notification_id: int, user: User) -> Notification:
        notification = self.db.execute(
            select(Notification).where(
                Notification.id == notification_id, Notification.user_id == user.id
            )
        ).scalar_one_or_none()
        if notification is None:
            # Scoped by user_id in the query, so another person's notification is simply
            # not found rather than forbidden.
            raise NotFoundError("Notification not found")

        if not notification.is_read:
            notification.is_read = True
            notification.read_at = datetime.now(UTC)
            self.db.commit()
        return notification

    def mark_all_read(self, user: User) -> int:
        result = self.db.execute(
            update(Notification)
            .where(Notification.user_id == user.id, Notification.is_read.is_(False))
            .values(is_read=True, read_at=datetime.now(UTC))
        )
        self.db.commit()
        return result.rowcount or 0

    def delete(self, notification_id: int, user: User) -> None:
        """Removes one notification from your own inbox.

        Safe to delete outright, unlike most things in this app: a notification is a
        copy of news, not the news itself. Removing "your result is available" does not
        touch the result, and the exam, the attempt and the marks are all still there.
        """
        notification = self.db.execute(
            select(Notification).where(
                Notification.id == notification_id, Notification.user_id == user.id
            )
        ).scalar_one_or_none()
        if notification is None:
            # Scoped by user_id, so someone else's notification is not found rather
            # than forbidden — the same rule mark_read follows.
            raise NotFoundError("Notification not found")
        self.db.delete(notification)
        self.db.commit()

    def clear_read(self, user: User) -> int:
        """Clears the ones already seen, and only those.

        Deliberately never touches unread notifications: "clear" should not be able to
        remove something the person has not read yet, which is exactly the thing they
        were most likely keeping.
        """
        result = self.db.execute(
            delete(Notification).where(
                Notification.user_id == user.id, Notification.is_read.is_(True)
            )
        )
        self.db.commit()
        return result.rowcount or 0

    # ------------------------------------------------------------- creating

    def _emit(
        self,
        user_ids: list[int],
        *,
        category: NotificationCategory,
        title: str,
        body: str,
        payload: dict[str, Any] | None = None,
    ) -> int:
        """Create one notification per recipient.

        Flushed, not committed: this runs inside the caller's transaction so a rolled-back
        action leaves no notification claiming it happened.
        """
        if not user_ids:
            return 0
        self.db.add_all(
            [
                Notification(
                    user_id=user_id,
                    category=category.value,
                    title=title,
                    body=body,
                    payload=payload,
                )
                for user_id in user_ids
            ]
        )
        self.db.flush()
        # Where a push channel would fan out. See docs/api.md §10 for what it needs.
        return len(user_ids)

    def _enrolled_student_ids(self, course_id: int) -> list[int]:
        return list(
            self.db.execute(
                select(CourseEnrollment.student_id).where(
                    CourseEnrollment.course_id == course_id
                )
            )
            .scalars()
            .all()
        )

    # --------------------------------------------------------- the events

    def exam_published(self, exam: Exam) -> int:
        """Everyone enrolled in the course, in one insert rather than one per student."""
        return self._emit(
            self._enrolled_student_ids(exam.course_id),
            category=NotificationCategory.EXAM_PUBLISHED,
            title=f"New exam: {exam.title}",
            body=f"{exam.course.course_code} — {exam.duration_minutes} minutes, "
            f"{exam.total_marks} marks. Ask your teacher to admit you.",
            payload={"exam_id": exam.id},
        )

    def join_request_received(self, exam: Exam, student: User) -> int:
        return self._emit(
            [exam.teacher_id],
            category=NotificationCategory.JOIN_REQUEST_RECEIVED,
            title="New join request",
            body=f"{student.name} asked to sit {exam.title}.",
            payload={"exam_id": exam.id},
        )

    def join_request_reviewed(self, exam: Exam, student_id: int, *, approved: bool) -> int:
        if approved:
            return self._emit(
                [student_id],
                category=NotificationCategory.JOIN_REQUEST_APPROVED,
                title="You are approved",
                body=f"You can sit {exam.title} when it opens.",
                payload={"exam_id": exam.id},
            )
        return self._emit(
            [student_id],
            category=NotificationCategory.JOIN_REQUEST_REJECTED,
            title="Request not approved",
            body=f"Your request to sit {exam.title} was not approved. "
            "Speak to your teacher; you can ask again.",
            payload={"exam_id": exam.id},
        )

    def exam_submitted(self, exam: Exam, student: User, *, auto: bool) -> int:
        return self._emit(
            [exam.teacher_id],
            category=NotificationCategory.EXAM_SUBMITTED,
            title="Exam submitted",
            body=f"{student.name} submitted {exam.title}"
            + (" (time ran out)." if auto else "."),
            payload={"exam_id": exam.id},
        )

    def results_published(self, exam: Exam, student_ids: list[int]) -> int:
        return self._emit(
            student_ids,
            category=NotificationCategory.RESULT_PUBLISHED,
            title="Result released",
            body=f"Your result for {exam.title} is available.",
            payload={"exam_id": exam.id},
        )
