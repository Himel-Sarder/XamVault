"""Join requests: a student asking to sit an exam, and the teacher's decision."""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.exceptions import ConflictError, InvalidRequestError, NotFoundError
from app.models.enums import ExamStatus, JoinRequestStatus
from app.models.exam import Exam
from app.models.join_request import JoinRequest
from app.models.user import User
from app.repositories.course_repository import CourseRepository
from app.repositories.exam_repository import ExamRepository
from app.repositories.join_request_repository import JoinRequestRepository
from app.schemas.join_request import StudentJoinRequestResponse
from app.services.notification_service import NotificationService
from app.services.student_exam_service import availability_of


class JoinRequestService:
    def __init__(self, db: Session) -> None:
        self.db = db
        self.requests = JoinRequestRepository(db)
        self.exams = ExamRepository(db)
        self.courses = CourseRepository(db)

    # --------------------------------------------------------- authorization

    def _exam_owned_by(self, exam_id: int, actor: User) -> Exam:
        exam = self.exams.get(exam_id)
        if exam is None:
            raise NotFoundError("Exam not found")
        if actor.is_admin or exam.teacher_id == actor.id:
            return exam
        raise NotFoundError("Exam not found")

    # ------------------------------------------------------------- student

    def request_to_join(self, exam_id: int, student: User) -> JoinRequest:
        exam = self.exams.get_for_student(exam_id, student.id)
        if exam is None:
            raise NotFoundError("Exam not found")
        if exam.status != ExamStatus.PUBLISHED:
            raise ConflictError("This exam is not open for requests")

        if availability_of(exam, datetime.now(UTC)) == "closed":
            raise ConflictError("This exam has already ended", code="exam_closed")

        existing = self.requests.get_for_student(exam_id, student.id)
        if existing is not None:
            if existing.is_pending:
                raise ConflictError(
                    "You already have a request waiting for approval",
                    code="request_pending",
                )
            if existing.is_approved:
                raise ConflictError(
                    "You have already been approved for this exam", code="already_approved"
                )
            # A rejected request may be replaced by a new attempt.

        request = JoinRequest(
            exam_id=exam.id,
            student_id=student.id,
            status=JoinRequestStatus.PENDING.value,
        )
        try:
            self.requests.add(request)
            NotificationService(self.db).join_request_received(exam, student)
            self.db.commit()
        except IntegrityError as error:
            # The partial unique index caught a duplicate created concurrently; the
            # check above narrows the race, the constraint closes it.
            self.db.rollback()
            raise ConflictError(
                "You already have a request waiting for approval", code="request_pending"
            ) from error
        return request

    def list_mine(self, student: User) -> list[StudentJoinRequestResponse]:
        rows = self.requests.list_for_student(student.id)
        return [
            StudentJoinRequestResponse(
                id=request.id,
                exam_id=exam.id,
                exam_title=exam.title,
                course_code=exam.course.course_code,
                status=request.status,
                requested_at=request.requested_at,
                reviewed_at=request.reviewed_at,
            )
            for request, exam in rows
        ]

    # ------------------------------------------------------------- teacher

    def list_for_exam(
        self, exam_id: int, actor: User, *, status: str | None
    ) -> list[JoinRequest]:
        self._exam_owned_by(exam_id, actor)
        if status is not None and status not in tuple(JoinRequestStatus):
            raise InvalidRequestError(f"Unknown status '{status}'")
        return self.requests.list_for_exam(exam_id, status=status)

    def review(self, request_id: int, actor: User, *, approve: bool) -> JoinRequest:
        request = self.requests.get(request_id)
        if request is None:
            raise NotFoundError("Request not found")
        # Ownership is checked against the exam, not the request: a teacher may only
        # decide on requests for their own exams.
        self._exam_owned_by(request.exam_id, actor)

        if not request.is_pending:
            raise ConflictError(
                f"This request has already been {request.status}",
                code="already_reviewed",
            )

        self._apply(request, actor, approve=approve)
        NotificationService(self.db).join_request_reviewed(
            request.exam, request.student_id, approved=approve
        )
        self.db.commit()
        return request

    def review_all(
        self, exam_id: int, actor: User, *, approve: bool, request_ids: list[int] | None
    ) -> int:
        """Bulk approve or reject, in one transaction (§31).

        Either every request in the batch is decided or none is, so a failure halfway
        cannot leave a class half-admitted.
        """
        self._exam_owned_by(exam_id, actor)
        pending = self.requests.list_for_exam(
            exam_id, status=JoinRequestStatus.PENDING.value
        )
        if request_ids is not None:
            wanted = set(request_ids)
            pending = [request for request in pending if request.id in wanted]

        notifications = NotificationService(self.db)
        exam = self.exams.get(exam_id)
        for request in pending:
            self._apply(request, actor, approve=approve)
            if exam is not None:
                notifications.join_request_reviewed(
                    exam, request.student_id, approved=approve
                )
        self.db.commit()
        return len(pending)

    @staticmethod
    def _apply(request: JoinRequest, actor: User, *, approve: bool) -> None:
        request.status = (
            JoinRequestStatus.APPROVED.value if approve else JoinRequestStatus.REJECTED.value
        )
        request.reviewed_at = datetime.now(UTC)
        request.reviewed_by = actor.id

    # --------------------------------------------------------------- shared

    def pending_count(self, exam_id: int, actor: User) -> int:
        self._exam_owned_by(exam_id, actor)
        return self.requests.count_pending(exam_id)
