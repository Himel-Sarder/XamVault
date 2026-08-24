from __future__ import annotations

from sqlalchemy import Select, func, select
from sqlalchemy.orm import Session, selectinload

from app.models.enums import JoinRequestStatus
from app.models.exam import Exam
from app.models.join_request import JoinRequest
from app.models.user import User


class JoinRequestRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    # ---------------------------------------------------------------- lookups

    def get(self, request_id: int) -> JoinRequest | None:
        return self.db.execute(
            select(JoinRequest)
            .where(JoinRequest.id == request_id)
            .options(
                selectinload(JoinRequest.student).selectinload(User.student_profile),
                selectinload(JoinRequest.exam),
            )
        ).scalar_one_or_none()

    def get_for_student(self, exam_id: int, student_id: int) -> JoinRequest | None:
        """The request that decides this student's access.

        A rejection may be followed by a new attempt, so the most recent row wins.
        """
        return self.db.execute(
            select(JoinRequest)
            .where(JoinRequest.exam_id == exam_id, JoinRequest.student_id == student_id)
            .order_by(JoinRequest.id.desc())
            .limit(1)
        ).scalar_one_or_none()

    def statuses_for_student(self, student_id: int, exam_ids: list[int]) -> dict[int, str]:
        """One query for a whole page of exams, instead of one per row."""
        if not exam_ids:
            return {}
        rows = self.db.execute(
            select(JoinRequest.exam_id, JoinRequest.status)
            .where(
                JoinRequest.student_id == student_id,
                JoinRequest.exam_id.in_(exam_ids),
            )
            .order_by(JoinRequest.exam_id, JoinRequest.id)
        ).all()
        # Later rows overwrite earlier ones, so the newest request per exam wins.
        return {exam_id: status for exam_id, status in rows}

    def _exam_query(self, exam_id: int, status: str | None) -> Select:
        stmt = select(JoinRequest).where(JoinRequest.exam_id == exam_id)
        if status is not None:
            stmt = stmt.where(JoinRequest.status == status)
        return stmt

    def list_for_exam(self, exam_id: int, *, status: str | None) -> list[JoinRequest]:
        stmt = (
            self._exam_query(exam_id, status)
            .options(selectinload(JoinRequest.student).selectinload(User.student_profile))
            .order_by(JoinRequest.requested_at, JoinRequest.id)
        )
        return list(self.db.execute(stmt).scalars().all())

    def count_pending(self, exam_id: int) -> int:
        return self.db.execute(
            select(func.count())
            .select_from(JoinRequest)
            .where(
                JoinRequest.exam_id == exam_id,
                JoinRequest.status == JoinRequestStatus.PENDING.value,
            )
        ).scalar_one()

    def list_for_student(self, student_id: int) -> list[tuple[JoinRequest, Exam]]:
        stmt = (
            select(JoinRequest, Exam)
            .join(Exam, Exam.id == JoinRequest.exam_id)
            .where(JoinRequest.student_id == student_id)
            .options(selectinload(Exam.course))
            .order_by(JoinRequest.requested_at.desc(), JoinRequest.id.desc())
        )
        return [(row[0], row[1]) for row in self.db.execute(stmt).all()]

    # ---------------------------------------------------------------- writes

    def add(self, request: JoinRequest) -> JoinRequest:
        self.db.add(request)
        self.db.flush()
        return request
