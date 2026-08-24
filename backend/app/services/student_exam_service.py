"""What a student is allowed to see about an exam.

Everything here is computed server-side. The client is told the availability window and
whether it may request to join; it never decides either (docs/security.md §3).
"""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy.orm import Session

from app.core.exceptions import NotFoundError
from app.models.enums import JoinRequestStatus
from app.models.exam import Exam
from app.models.user import User
from app.repositories.exam_repository import ExamRepository
from app.repositories.join_request_repository import JoinRequestRepository
from app.schemas.exam import StudentExamResponse, StudentExamSettings

NO_REQUEST = "none"


def availability_of(exam: Exam, now: datetime) -> str:
    """`upcoming` before the window, `open` inside it, `closed` after."""
    if exam.start_at is None:
        return "upcoming"
    if now < exam.start_at:
        return "upcoming"
    if exam.expires_at is not None and now >= exam.expires_at:
        return "closed"
    return "open"


class StudentExamService:
    def __init__(self, db: Session) -> None:
        self.db = db
        self.exams = ExamRepository(db)
        self.join_requests = JoinRequestRepository(db)

    def list_available(
        self, student: User, *, offset: int, limit: int, include_closed: bool
    ) -> tuple[list[StudentExamResponse], int]:
        now = datetime.now(UTC)
        exams, total = self.exams.list_available_for_student(
            student.id, now=now, offset=offset, limit=limit, include_closed=include_closed
        )
        # One query for the whole page rather than one per exam.
        statuses = self.join_requests.statuses_for_student(
            student.id, [exam.id for exam in exams]
        )
        return [self._present(exam, statuses.get(exam.id, NO_REQUEST), now) for exam in exams], total

    def get(self, exam_id: int, student: User) -> StudentExamResponse:
        exam = self.exams.get_for_student(exam_id, student.id)
        if exam is None:
            # 404 whether the exam is another cohort's, still a draft, or absent: the
            # student cannot tell which, so nothing is disclosed.
            raise NotFoundError("Exam not found")
        request = self.join_requests.get_for_student(exam_id, student.id)
        return self._present(exam, request.status if request else NO_REQUEST, datetime.now(UTC))

    @staticmethod
    def _present(exam: Exam, join_status: str, now: datetime) -> StudentExamResponse:
        availability = availability_of(exam, now)
        settings = exam.settings
        return StudentExamResponse(
            id=exam.id,
            course_id=exam.course_id,
            course_code=exam.course.course_code,
            course_name=exam.course.course_name,
            title=exam.title,
            description=exam.description,
            start_at=exam.start_at,
            duration_minutes=exam.duration_minutes,
            expires_at=exam.expires_at,
            total_marks=exam.total_marks,
            question_count=len(exam.questions),
            availability=availability,
            join_request_status=join_status,
            # Asking is only useful while the exam can still be sat, and only once.
            can_request_join=(
                availability != "closed"
                and join_status in (NO_REQUEST, JoinRequestStatus.REJECTED.value)
            ),
            settings=StudentExamSettings(
                secure_mode=settings.secure_mode if settings else True,
                allow_back_navigation=settings.allow_back_navigation if settings else True,
                max_attempts=settings.max_attempts if settings else 1,
            ),
        )
