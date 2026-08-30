"""The exam attempt engine (§32–§43).

Three rules run through this module:

* **The server owns time.** ``started_at`` and ``expires_at`` are written once, here, and
  every later decision compares the server clock to them. A client can send whatever it
  likes; none of it is read.
* **The server owns the answer key.** Grading reads the frozen snapshot taken at publish,
  never the live question and never anything the client sent.
* **Order is fixed at creation.** A student's shuffle is generated once and stored, so
  the paper does not rearrange itself underneath them.
"""

from __future__ import annotations

import random
from datetime import UTC, datetime
from decimal import Decimal
from typing import Any

from sqlalchemy import update
from sqlalchemy.orm import Session

from fastapi import UploadFile

from app.core.exceptions import (
    ConflictError,
    InvalidRequestError,
    NotFoundError,
    PermissionDeniedError,
)
from app.models.attempt import ExamAttempt, StudentAnswer
from app.models.enums import (
    CHOICE_QUESTION_TYPES,
    MANUAL_QUESTION_TYPES,
    AnswerStatus,
    AttemptStatus,
    ExamStatus,
    JoinRequestStatus,
    QuestionType,
    ResultStatus,
)
from app.models.exam import Exam, ExamQuestion
from app.models.result import Result
from app.models.user import User
from app.repositories.attempt_repository import AttemptRepository
from app.repositories.course_repository import CourseRepository
from app.services.upload_service import UploadService
from app.repositories.exam_repository import ExamRepository
from app.repositories.join_request_repository import JoinRequestRepository
from app.services.notification_service import NotificationService


class AttemptService:
    def __init__(self, db: Session) -> None:
        self.db = db
        self.attempts = AttemptRepository(db)
        self.exams = ExamRepository(db)
        self.courses = CourseRepository(db)
        self.join_requests = JoinRequestRepository(db)

    # ------------------------------------------------------------------ start

    def start(self, exam_id: int, student: User) -> ExamAttempt:
        """Every condition in §32, checked here and nowhere else."""
        now = datetime.now(UTC)

        # 1-2. Published, and in a course this student is enrolled in. The query itself
        #      enforces both, so neither can be forgotten.
        exam = self.exams.get_for_student(exam_id, student.id)
        if exam is None:
            raise NotFoundError("Exam not found")

        # 3. The exam is still published (not cancelled or completed since).
        if exam.status != ExamStatus.PUBLISHED:
            raise ConflictError("This exam is not open", code="exam_not_open")

        # 4. A teacher has admitted this student to this sitting -- unless the exam is
        #    set to admit anyone enrolled.
        #
        #    Enrolment is not waived by that setting: step 1-2 above already required
        #    it, and this only decides whether a second gate exists. An exam nobody has
        #    to be approved for is still an exam only its own course can sit.
        settings = exam.settings
        if not (settings and settings.auto_approve_join):
            request = self.join_requests.get_for_student(exam_id, student.id)
            if request is None or request.status != JoinRequestStatus.APPROVED:
                raise PermissionDeniedError(
                    "Your teacher has not approved you for this exam yet",
                    code="not_approved",
                )
        else:
            # An explicit rejection still stands. Opening the doors is not a licence to
            # readmit somebody a teacher deliberately turned away.
            request = self.join_requests.get_for_student(exam_id, student.id)
            if request is not None and request.status == JoinRequestStatus.REJECTED:
                raise PermissionDeniedError(
                    "Your teacher has not approved you for this exam",
                    code="not_approved",
                )

        # 5-6. Inside the exam window, by the server clock.
        if exam.start_at is None or now < exam.start_at:
            raise ConflictError("This exam has not started yet", code="not_started")
        if exam.expires_at is not None and now >= exam.expires_at:
            raise ConflictError("This exam has already ended", code="exam_closed")

        # 7. Resume rather than duplicate: an app restart must return the same attempt,
        #    with the same clock and the same question order (§60).
        existing = self.attempts.get_active_for(exam_id, student.id)
        if existing is not None:
            if existing.has_expired(now):
                self._finish(existing, now, AttemptStatus.AUTO_SUBMITTED)
                self.db.commit()
                raise ConflictError(
                    "Your time for this exam has run out", code="attempt_expired"
                )
            return existing

        # 8. Attempts already used up.
        settings = exam.settings
        max_attempts = settings.max_attempts if settings else 1
        if self.attempts.count_for(exam_id, student.id) >= max_attempts:
            raise ConflictError(
                "You have already used all your attempts at this exam",
                code="no_attempts_left",
            )

        links = self.exams.list_exam_questions(exam.id)
        if not links:
            raise ConflictError("This exam has no questions", code="exam_empty")

        attempt = self.attempts.add(
            ExamAttempt(
                exam_id=exam.id,
                student_id=student.id,
                started_at=now,
                # A late start does not extend the exam past its own window.
                expires_at=self._deadline(exam, now),
                status=AttemptStatus.ACTIVE.value,
                question_order=self._question_order(links, shuffle=bool(settings and settings.shuffle_questions)),
                option_orders=self._option_orders(links, shuffle=bool(settings and settings.shuffle_answers)),
            )
        )
        self.db.commit()
        return attempt

    @staticmethod
    def _deadline(exam: Exam, started_at: datetime) -> datetime:
        personal = started_at + exam.duration_window()
        if exam.expires_at is None:
            return personal
        return min(personal, exam.expires_at)

    @staticmethod
    def _question_order(links: list[ExamQuestion], *, shuffle: bool) -> list[int]:
        order = [link.id for link in links]
        if shuffle:
            random.shuffle(order)
        return order

    @staticmethod
    def _option_orders(links: list[ExamQuestion], *, shuffle: bool) -> dict[str, list[int]]:
        """Option *ids* in this student's order — never letters.

        The letter a student saw is meaningless at grading time; the id is what identifies
        the choice (§36). JSON object keys must be strings, hence the ``str(...)``.
        """
        orders: dict[str, list[int]] = {}
        for link in links:
            snapshot = link.question_snapshot or {}
            # Written answers have no options; the key is still present so the shape of
            # option_orders matches question_order exactly.
            ids = [option["id"] for option in snapshot.get("options", [])]
            if shuffle:
                random.shuffle(ids)
            orders[str(link.id)] = ids
        return orders

    # --------------------------------------------------------------- reading

    def get(self, attempt_id: int, student: User) -> ExamAttempt:
        """Load an attempt, auto-submitting it first if its time has run out.

        Doing the expiry check on read means a student who closes the app at the
        deadline and returns later finds a submitted attempt, not a live one.
        """
        attempt = self.attempts.get(attempt_id)
        if attempt is None:
            raise NotFoundError("Attempt not found")
        if attempt.student_id != student.id:
            # 404, not 403: another student's attempt is not theirs to know about.
            raise NotFoundError("Attempt not found")

        now = datetime.now(UTC)
        if attempt.is_active and attempt.has_expired(now):
            self._finish(attempt, now, AttemptStatus.AUTO_SUBMITTED)
            self.db.commit()
        return attempt

    def build_view(self, attempt: ExamAttempt) -> dict[str, Any]:
        """The attempt as the student may see it: questions in *their* order, options in
        *their* order, and not one field of the answer key."""
        now = datetime.now(UTC)
        exam = attempt.exam
        links = {link.id: link for link in self.exams.list_exam_questions(exam.id)}
        answers = {answer.exam_question_id: answer for answer in attempt.answers}

        questions: list[dict[str, Any]] = []
        for position, link_id in enumerate(attempt.question_order, start=1):
            link = links.get(link_id)
            if link is None:  # pragma: no cover - the exam is frozen once published
                continue
            snapshot = link.question_snapshot or {}
            by_id = {option["id"]: option for option in snapshot.get("options", [])}
            ordered_ids = attempt.option_orders.get(str(link_id), list(by_id))
            answer = answers.get(link_id)
            questions.append(
                {
                    "exam_question_id": link.id,
                    "position": position,
                    "type": snapshot.get("type", ""),
                    "question_text": snapshot.get("question_text", ""),
                    "question_image_url": snapshot.get("question_image_url"),
                    "marks": link.marks_snapshot,
                    "options": [
                        {
                            "id": by_id[option_id]["id"],
                            "option_text": by_id[option_id].get("option_text"),
                            "option_image_url": by_id[option_id].get("option_image_url"),
                        }
                        for option_id in ordered_ids
                        if option_id in by_id
                    ],
                    "selected_option_id": answer.selected_option_id if answer else None,
                    "answer_text": answer.answer_text if answer else None,
                    "answer_image_urls": list(answer.answer_image_urls or [])
                    if answer
                    else [],
                    # Shown next to the code editor so the student knows the rules.
                    "language": snapshot.get("language"),
                    "time_limit_seconds": snapshot.get("time_limit_seconds"),
                    "memory_limit_mb": snapshot.get("memory_limit_mb"),
                }
            )

        settings = exam.settings
        return {
            "id": attempt.id,
            "exam_id": exam.id,
            "exam_title": exam.title,
            "course_code": exam.course.course_code,
            "status": attempt.status,
            "started_at": attempt.started_at,
            "expires_at": attempt.expires_at,
            "submitted_at": attempt.submitted_at,
            "remaining_seconds": attempt.remaining_seconds(now),
            "server_time": now,
            "duration_minutes": exam.duration_minutes,
            "total_marks": exam.total_marks,
            "allow_back_navigation": settings.allow_back_navigation if settings else True,
            "secure_mode": settings.secure_mode if settings else True,
            "questions": questions,
            "answered_count": sum(1 for answer in attempt.answers if answer.is_answered),
            "total_questions": len(questions),
        }

    # --------------------------------------------------------------- answering

    def save_answer(
        self,
        attempt_id: int,
        student: User,
        *,
        exam_question_id: int,
        selected_option_id: int | None = None,
        answer_text: str | None = None,
    ) -> tuple[ExamAttempt, StudentAnswer]:
        attempt = self.get(attempt_id, student)
        now = datetime.now(UTC)

        if not attempt.is_active:
            raise ConflictError(
                "This attempt has been submitted and can no longer be changed",
                code="attempt_closed",
            )
        if attempt.has_expired(now):  # pragma: no cover - get() already auto-submits
            raise ConflictError("Your time for this exam has run out", code="attempt_expired")

        if exam_question_id not in attempt.question_order:
            raise NotFoundError("That question is not part of this attempt")

        question_type = self._question_type(attempt, exam_question_id)

        if question_type in CHOICE_QUESTION_TYPES:
            if answer_text:
                raise InvalidRequestError(
                    "This question is answered by choosing an option, not by typing"
                )
            # An option id from a different question - or invented outright - is rejected
            # rather than stored and silently marked wrong later.
            if selected_option_id is not None:
                allowed = attempt.option_orders.get(str(exam_question_id), [])
                if selected_option_id not in allowed:
                    raise InvalidRequestError("That option does not belong to this question")
        else:
            if selected_option_id is not None:
                raise InvalidRequestError("This question is answered in writing")
            answer_text = (answer_text or "").strip() or None

        answer = self.attempts.get_answer(attempt.id, exam_question_id)
        if answer is None:
            answer = self.attempts.add_answer(
                StudentAnswer(
                    attempt_id=attempt.id,
                    exam_question_id=exam_question_id,
                    selected_option_id=selected_option_id,
                    answer_text=answer_text,
                    status=AnswerStatus.PENDING.value,
                )
            )
        else:
            answer.selected_option_id = selected_option_id
            answer.answer_text = answer_text
            answer.updated_at = now

        self.db.commit()
        self.db.refresh(attempt, ["answers"])
        return attempt, answer

    # ----------------------------------------------------------- photographs

    def _question_type(self, attempt: ExamAttempt, exam_question_id: int) -> str:
        link = self.exams.get_exam_question(attempt.exam_id, exam_question_id)
        snapshot = (link.question_snapshot if link else None) or {}
        return str(snapshot.get("type", ""))

    # -------------------------------------------------------------- submitting

    def submit(self, attempt_id: int, student: User) -> ExamAttempt:
        attempt = self.attempts.get(attempt_id)
        if attempt is None or attempt.student_id != student.id:
            raise NotFoundError("Attempt not found")

        now = datetime.now(UTC)
        if not attempt.is_active:
            raise ConflictError(
                "This attempt has already been submitted", code="already_submitted"
            )

        # A submission that arrives after the deadline is recorded as auto-submitted:
        # accurate about what happened, and it still saves the student's answers.
        status = (
            AttemptStatus.AUTO_SUBMITTED if attempt.has_expired(now) else AttemptStatus.SUBMITTED
        )
        self._finish(attempt, now, status)
        self.db.commit()
        self.db.refresh(attempt)
        return attempt

    def _finish(self, attempt: ExamAttempt, now: datetime, status: AttemptStatus) -> Result:
        """Close an attempt and score it, in one transaction (§41).

        The guarded UPDATE is what makes this safe: two submissions racing each other
        both try to move the row out of ``active`` and only one can win, so an attempt
        can never be graded twice.
        """
        changed = self.db.execute(
            update(ExamAttempt)
            .where(
                ExamAttempt.id == attempt.id,
                ExamAttempt.status == AttemptStatus.ACTIVE.value,
            )
            .values(status=status.value, submitted_at=now)
        )
        if (changed.rowcount or 0) == 0:
            existing = self.attempts.get_result_for_attempt(attempt.id)
            if existing is not None:
                return existing
            raise ConflictError(
                "This attempt has already been submitted", code="already_submitted"
            )

        attempt.status = status.value
        attempt.submitted_at = now

        NotificationService(self.db).exam_submitted(
            attempt.exam,
            attempt.student,
            auto=status is AttemptStatus.AUTO_SUBMITTED,
        )
        return self._grade(attempt, now)

    # ---------------------------------------------------------------- grading

    def _grade(self, attempt: ExamAttempt, now: datetime) -> Result:
        """Mark what a machine can, and leave the rest for a person.

        Choice questions are scored here, against the snapshot frozen at publish. Short
        answers and code are left ``pending`` for the teacher (§43); their scores stay at
        zero until someone marks them, and :meth:`recompute_result` folds them in.
        """
        exam = attempt.exam
        links = {link.id: link for link in self.exams.list_exam_questions(exam.id)}
        answers = {answer.exam_question_id: answer for answer in attempt.answers}

        for link_id in attempt.question_order:
            link = links.get(link_id)
            if link is None:  # pragma: no cover - frozen exam
                continue
            snapshot = link.question_snapshot or {}
            answer = answers.get(link_id)
            if answer is None:
                continue

            if snapshot.get("type") in CHOICE_QUESTION_TYPES:
                correct_ids = {
                    option["id"]
                    for option in snapshot.get("options", [])
                    if option.get("is_correct")
                }
                answer.marks_awarded = (
                    Decimal(link.marks_snapshot)
                    if answer.selected_option_id in correct_ids
                    else Decimal("0")
                )
                answer.status = AnswerStatus.EVALUATED.value
                answer.evaluated_at = now
            else:
                # Awaiting a human. Left explicitly unmarked rather than scored zero, so
                # "not yet marked" and "marked zero" stay distinguishable.
                answer.marks_awarded = None
                answer.status = AnswerStatus.PENDING.value

        self.db.flush()
        return self.recompute_result(attempt, now=now)

    def recompute_result(self, attempt: ExamAttempt, *, now: datetime | None = None) -> Result:
        """Rebuild the result from the answers as they currently stand.

        Called at submission and again after every manual mark, so the total is always
        the sum of what has actually been awarded.
        """
        now = now or datetime.now(UTC)
        exam = attempt.exam
        links = {link.id: link for link in self.exams.list_exam_questions(exam.id)}

        totals = {"mcq": Decimal("0"), "short": Decimal("0"), "code": Decimal("0")}
        for answer in attempt.answers:
            link = links.get(answer.exam_question_id)
            if link is None or answer.marks_awarded is None:
                continue
            kind = (link.question_snapshot or {}).get("type", "")
            awarded = Decimal(str(answer.marks_awarded))
            if kind in CHOICE_QUESTION_TYPES:
                totals["mcq"] += awarded
            elif kind == QuestionType.CODE_ANSWER:
                totals["code"] += awarded
            else:
                # Everything else marked by hand -- a typed short answer, or a
                # photograph of work done on paper -- counts as written.
                #
                # An else rather than one more elif. The chain used to name each type
                # it accepted, so a manually marked type added later matched none of
                # them: a teacher could award marks, see them stored against the
                # answer, and watch the total stay at zero. A type
                # this code has not heard of must land somewhere, not nowhere.
                totals["short"] += awarded

        total = totals["mcq"] + totals["short"] + totals["code"]
        possible = exam.total_marks or 0
        percentage = (total / Decimal(possible) * 100) if possible else Decimal("0")

        result = self.attempts.get_result_for_attempt(attempt.id)
        if result is None:
            result = self.attempts.add_result(
                Result(exam_id=exam.id, student_id=attempt.student_id, attempt_id=attempt.id)
            )
        result.mcq_score = totals["mcq"]
        result.short_answer_score = totals["short"]
        result.code_score = totals["code"]
        result.total_score = total
        result.percentage = round(percentage, 2)

        # An exam that still needs marking is never released automatically, however the
        # teacher configured it: a partial score shown as final would be wrong.
        settings = exam.settings
        awaiting = self.count_pending_manual(attempt)
        if awaiting == 0 and settings and settings.show_result_immediately:
            result.status = ResultStatus.PUBLISHED.value
            result.published_at = result.published_at or now
        elif result.status != ResultStatus.PUBLISHED:
            result.status = ResultStatus.PENDING.value

        self.db.flush()
        return result

    def count_pending_manual(self, attempt: ExamAttempt) -> int:
        """Answers a teacher still has to mark."""
        links = {link.id: link for link in self.exams.list_exam_questions(attempt.exam_id)}
        pending = 0
        for answer in attempt.answers:
            if answer.status != AnswerStatus.PENDING:
                continue
            link = links.get(answer.exam_question_id)
            if link is None:  # pragma: no cover - frozen exam
                continue
            if (link.question_snapshot or {}).get("type") in MANUAL_QUESTION_TYPES:
                pending += 1
        return pending

    # ------------------------------------------------------------ auto-submit

    def sweep_expired(self, *, limit: int = 200) -> int:
        """Close and grade attempts whose time ran out while nobody was looking (§42).

        The app also asks the server to submit when its own countdown reaches zero, but
        that only helps if the app is still running. This is the backstop, and is safe to
        call repeatedly; a scheduled worker should call it in production.
        """
        now = datetime.now(UTC)
        overdue = self.attempts.list_overdue(now, limit=limit)
        for attempt in overdue:
            self._finish(attempt, now, AttemptStatus.AUTO_SUBMITTED)
        if overdue:
            self.db.commit()
        return len(overdue)
