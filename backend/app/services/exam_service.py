"""Exams: creation, configuration, question management and publishing.

Two rules run through everything here:

* **Ownership.** Being a teacher is never enough — the exam's ``teacher_id`` (or the
  course's ``created_by``) must be the caller.
* **Draft-only edits.** Once published, an exam is frozen. Students may already have
  seen it, so changing its questions or timing afterwards would rewrite history.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Any

from sqlalchemy.orm import Session

from app.core.exceptions import ConflictError, NotFoundError, ValidationIssuesError
from app.models.enums import (
    CHOICE_QUESTION_TYPES,
    EDITABLE_EXAM_STATUSES,
    IMAGE_STEM_TYPES,
    ExamStatus,
    QuestionType,
)
from app.models.exam import Exam, ExamQuestion, ExamSettings
from app.models.question import Question, QuestionOption
from app.models.user import User
from app.repositories.attempt_repository import AttemptRepository
from app.repositories.exam_repository import ExamRepository
from app.repositories.question_repository import QuestionRepository
from app.schemas.exam import ExamCreate, ExamSettingsUpdate, ExamUpdate
from app.schemas.question import QuestionCreate
from app.services.course_service import CourseService
from app.services.notification_service import NotificationService


class ExamService:
    def __init__(self, db: Session) -> None:
        self.db = db
        self.exams = ExamRepository(db)
        self.questions = QuestionRepository(db)
        self.attempts = AttemptRepository(db)
        self.courses = CourseService(db)

    # --------------------------------------------------------- authorization

    def _get_owned(self, exam_id: int, actor: User) -> Exam:
        """404 rather than 403 for someone else's exam: confirming that exam 42 exists
        is itself a disclosure."""
        exam = self.exams.get(exam_id)
        if exam is None:
            raise NotFoundError("Exam not found")
        if actor.is_admin or exam.teacher_id == actor.id:
            return exam
        raise NotFoundError("Exam not found")

    @staticmethod
    def _assert_editable(exam: Exam) -> None:
        if exam.status not in EDITABLE_EXAM_STATUSES:
            raise ConflictError(
                f"This exam is {exam.status} and can no longer be edited. "
                "Only draft exams can be changed.",
                code="exam_not_editable",
            )

    # ----------------------------------------------------------------- reads

    def list_for_teacher(
        self,
        actor: User,
        *,
        course_id: int | None,
        status: str | None,
        offset: int,
        limit: int,
    ) -> tuple[list[Exam], int]:
        if course_id is not None:
            # Raises if the course is not the caller's, so a probe cannot enumerate
            # another teacher's course ids through this filter.
            self.courses.assert_can_manage(course_id, actor)
        return self.exams.list_for_teacher(
            # An admin can already open any exam, so the list shows all of them rather
            # than only the (usually zero) exams they authored themselves.
            None if actor.is_admin else actor.id,
            course_id=course_id,
            status=status,
            offset=offset,
            limit=limit,
        )

    def get_for_teacher(self, exam_id: int, actor: User) -> Exam:
        self._get_owned(exam_id, actor)
        exam = self.exams.get_full(exam_id)
        if exam is None:  # pragma: no cover - removed between the two reads
            raise NotFoundError("Exam not found")
        return exam

    def list_questions(self, exam_id: int, actor: User) -> list[ExamQuestion]:
        self._get_owned(exam_id, actor)
        return self.exams.list_exam_questions(exam_id)

    # -------------------------------------------------------- exam lifecycle

    def create(self, data: ExamCreate, actor: User) -> Exam:
        self.courses.assert_can_manage(data.course_id, actor)

        exam = self.exams.add(
            Exam(
                course_id=data.course_id,
                teacher_id=actor.id,  # from the token, never the request body
                title=data.title.strip(),
                description=data.description,
                start_at=data.start_at,
                duration_minutes=data.duration_minutes,
                total_marks=0,  # derived from questions, never supplied
                status=ExamStatus.DRAFT.value,
            )
        )
        settings = ExamSettings(exam_id=exam.id)
        if data.settings is not None:
            for field, value in data.settings.model_dump(exclude_none=True).items():
                setattr(settings, field, value)
        self.exams.add_settings(settings)

        self.db.commit()
        return self.get_for_teacher(exam.id, actor)

    def update(self, exam_id: int, data: ExamUpdate, actor: User) -> Exam:
        exam = self._get_owned(exam_id, actor)
        self._assert_editable(exam)
        for field, value in data.model_dump(exclude_unset=True).items():
            setattr(exam, field, value)
        self.db.commit()
        return self.get_for_teacher(exam.id, actor)

    def update_settings(
        self, exam_id: int, data: ExamSettingsUpdate, actor: User
    ) -> Exam:
        exam = self._get_owned(exam_id, actor)
        self._assert_editable(exam)
        settings = exam.settings or self.exams.add_settings(ExamSettings(exam_id=exam.id))
        for field, value in data.model_dump(exclude_none=True).items():
            setattr(settings, field, value)
        self.db.commit()
        return self.get_for_teacher(exam.id, actor)

    def delete(self, exam_id: int, actor: User) -> None:
        """Removes an exam nobody has sat.

        The gate is attempts, not status. A published exam that no student ever opened
        holds nothing worth keeping, and refusing to remove it would leave a teacher's
        list full of mistakes they cannot clear. One attempt is different: it is a
        student's record, and deleting the exam would take their answers, marks and
        result with it. That case is offered :meth:`cancel` instead, which stops the
        exam without destroying what happened during it.
        """
        exam = self._get_owned(exam_id, actor)
        sat = self.attempts.count_for_exam(exam.id)
        if sat:
            raise ConflictError(
                f"{sat} student{'s have' if sat != 1 else ' has'} already sat this exam, "
                "so deleting it would delete their answers and results. Cancel it "
                "instead — that stops it without losing the record.",
                code="exam_has_attempts",
            )
        # Cascades remove the settings and the question links. The questions themselves
        # survive in the teacher's library, where they can be reused or deleted
        # deliberately.
        self.exams.delete(exam)
        self.db.commit()

    def cancel(self, exam_id: int, actor: User) -> Exam:
        """Stops an exam without destroying anything it produced.

        Nothing is removed: attempts, answers and released results all stay readable.
        A cancelled exam simply is not ``published`` any more, and starting an attempt
        already requires that, so no new sitting can begin.
        """
        exam = self._get_owned(exam_id, actor)
        if exam.status == ExamStatus.CANCELLED.value:
            raise ConflictError("This exam is already cancelled", code="already_cancelled")
        if exam.status == ExamStatus.DRAFT.value:
            raise ConflictError(
                "A draft has not started, so there is nothing to cancel. Delete it "
                "instead.",
                code="exam_not_started",
            )
        exam.status = ExamStatus.CANCELLED.value
        self.db.commit()
        return self.get_for_teacher(exam.id, actor)

    # ------------------------------------------------------------- questions

    def add_question(self, exam_id: int, data: QuestionCreate, actor: User) -> ExamQuestion:
        exam = self._get_owned(exam_id, actor)
        self._assert_editable(exam)

        question = self.questions.add(
            Question(
                type=data.type,
                question_text=data.question_text.strip(),
                question_image_url=data.question_image_url,
                marks=data.marks,
                difficulty=data.difficulty,
                topic=data.topic,
                language=data.language,
                time_limit_seconds=data.time_limit_seconds,
                memory_limit_mb=data.memory_limit_mb,
                created_by=actor.id,
            )
        )
        for order, option in enumerate(data.options):
            self.questions.add_option(
                QuestionOption(
                    question_id=question.id,
                    option_text=(option.option_text or "").strip() or None,
                    option_image_url=option.option_image_url,
                    display_order=order,
                    is_correct=option.is_correct,
                )
            )

        link = self.exams.add_exam_question(
            ExamQuestion(
                exam_id=exam.id,
                question_id=question.id,
                marks_snapshot=data.marks,
                display_order=self.exams.next_display_order(exam.id),
            )
        )
        self._recalculate_total_marks(exam)
        self.db.commit()
        self.db.refresh(link)
        return link

    def update_question(
        self, exam_id: int, exam_question_id: int, data: QuestionCreate, actor: User
    ) -> ExamQuestion:
        exam = self._get_owned(exam_id, actor)
        self._assert_editable(exam)

        link = self.exams.get_exam_question(exam.id, exam_question_id)
        if link is None:
            raise NotFoundError("That question is not part of this exam")

        question = self.questions.get(link.question_id)
        if question is None:  # pragma: no cover - FK makes this unreachable
            raise NotFoundError("Question not found")

        question.type = data.type
        question.question_text = data.question_text.strip()
        question.question_image_url = data.question_image_url
        question.marks = data.marks
        question.difficulty = data.difficulty
        question.topic = data.topic
        question.language = data.language
        question.time_limit_seconds = data.time_limit_seconds
        question.memory_limit_mb = data.memory_limit_mb
        self.questions.replace_options(
            question,
            [
                QuestionOption(
                    option_text=(option.option_text or "").strip() or None,
                    option_image_url=option.option_image_url,
                    display_order=order,
                    is_correct=option.is_correct,
                )
                for order, option in enumerate(data.options)
            ],
        )

        link.marks_snapshot = data.marks
        self._recalculate_total_marks(exam)
        self.db.commit()
        self.db.refresh(link)
        return link

    def remove_question(self, exam_id: int, exam_question_id: int, actor: User) -> None:
        exam = self._get_owned(exam_id, actor)
        self._assert_editable(exam)

        link = self.exams.get_exam_question(exam.id, exam_question_id)
        if link is None:
            raise NotFoundError("That question is not part of this exam")

        self.exams.delete_exam_question(link)
        # The question itself stays. It is a library entry (Phase 6) that may be reused
        # in another exam, so removing it from *this* paper must not destroy it —
        # deleting a question is an explicit act, through the question bank.
        self._resequence(exam.id)
        self._recalculate_total_marks(exam)
        self.db.commit()

    def reorder_questions(
        self, exam_id: int, ordered_ids: list[int], actor: User
    ) -> list[ExamQuestion]:
        exam = self._get_owned(exam_id, actor)
        self._assert_editable(exam)

        links = self.exams.list_exam_questions(exam.id)
        known = {link.id for link in links}
        if set(ordered_ids) != known:
            raise ValidationIssuesError(
                "The new order must list every question in this exam exactly once",
                [{"field": "question_ids", "message": "Order does not match the exam's questions"}],
            )
        position = {link_id: index for index, link_id in enumerate(ordered_ids)}
        for link in links:
            link.display_order = position[link.id]
        self.db.commit()
        return self.exams.list_exam_questions(exam.id)

    # ---------------------------------------------------------------- helpers

    def _recalculate_total_marks(self, exam: Exam) -> None:
        """``total_marks`` is always derived, never accepted from a client (§63)."""
        self.db.flush()
        exam.total_marks = self.exams.sum_marks(exam.id)

    def _resequence(self, exam_id: int) -> None:
        """Keep display_order contiguous after a removal, so the palette a student sees
        has no gaps."""
        for index, link in enumerate(self.exams.list_exam_questions(exam_id)):
            link.display_order = index

    # --------------------------------------------------------------- publish

    def publish_issues(self, exam_id: int, actor: User) -> list[dict[str, str]]:
        """Every reason this exam cannot be published (§28), so the teacher sees the
        whole list instead of discovering them one retry at a time."""
        exam = self._get_owned(exam_id, actor)
        return self._collect_publish_issues(exam)

    def _collect_publish_issues(self, exam: Exam) -> list[dict[str, str]]:
        issues: list[dict[str, str]] = []

        def add(field: str, message: str) -> None:
            issues.append({"field": field, "message": message})

        links = self.exams.list_exam_questions(exam.id)
        if not links:
            add("questions", "Add at least one question before publishing")

        if exam.start_at is None:
            add("start_at", "Set the date and time the exam starts")
        else:
            ends_at = exam.start_at + timedelta(minutes=exam.duration_minutes)
            if ends_at <= datetime.now(UTC):
                add("start_at", "The exam window has already passed; choose a future start time")

        total = sum(link.marks_snapshot for link in links)
        if links and total <= 0:
            add("total_marks", "Total marks must be greater than zero")

        for link in links:
            question = link.question
            label = f"Question {link.display_order + 1}"

            if question.type in CHOICE_QUESTION_TYPES:
                if len(question.options) < 2:
                    add("questions", f"{label} needs at least two options")
                if len(question.correct_option_ids) != 1:
                    add("questions", f"{label} must have exactly one correct answer")
                if question.type == QuestionType.IMAGE_IMAGE_OPTIONS and any(
                    not option.option_image_url for option in question.options
                ):
                    add("questions", f"{label} has an option with no image")

            if question.type in IMAGE_STEM_TYPES and not question.question_image_url:
                add("questions", f"{label} needs its question image")

            if question.type == QuestionType.CODE_ANSWER and not question.language:
                add("questions", f"{label} needs a programming language")

            if not question.question_text.strip():
                add("questions", f"{label} has no question text")

        if not exam.course.is_active:
            add("course", "The course this exam belongs to is archived")

        return issues

    def publish(self, exam_id: int, actor: User) -> Exam:
        exam = self._get_owned(exam_id, actor)

        if exam.status == ExamStatus.PUBLISHED:
            raise ConflictError("This exam is already published", code="already_published")
        if exam.status not in EDITABLE_EXAM_STATUSES:
            raise ConflictError(
                f"An exam that is {exam.status} cannot be published",
                code="exam_not_publishable",
            )

        issues = self._collect_publish_issues(exam)
        if issues:
            raise ValidationIssuesError("This exam is not ready to publish", issues)

        now = datetime.now(UTC)
        links = self.exams.list_exam_questions(exam.id)

        # Freeze each question. From here the exam renders from these snapshots, so
        # editing the source question - or reusing it in another exam - cannot change
        # what students were shown (§17).
        for link in links:
            question = self.questions.get(link.question_id)
            if question is None:  # pragma: no cover - FK makes this unreachable
                continue
            link.question_snapshot = self._snapshot(question)
            link.marks_snapshot = question.marks

        exam.total_marks = sum(link.marks_snapshot for link in links)
        exam.expires_at = exam.start_at + timedelta(minutes=exam.duration_minutes)
        exam.status = ExamStatus.PUBLISHED.value
        exam.published_at = now

        # Inside the same transaction: if publishing rolls back, nobody was told it
        # happened.
        NotificationService(self.db).exam_published(exam)

        # One transaction: an exam is never half-published with some questions frozen.
        self.db.commit()
        return self.get_for_teacher(exam.id, actor)

    @staticmethod
    def _snapshot(question: Question) -> dict[str, Any]:
        """The frozen form of a question.

        Includes ``is_correct`` deliberately: grading (Phase 13) must score against what
        the student actually saw, not against a question that may since have been edited.
        This value is never serialised to a student - only teacher schemas expose it.
        """
        return {
            "id": question.id,
            "type": question.type,
            "question_text": question.question_text,
            "question_image_url": question.question_image_url,
            "marks": question.marks,
            "difficulty": question.difficulty,
            "topic": question.topic,
            "language": question.language,
            "time_limit_seconds": question.time_limit_seconds,
            "memory_limit_mb": question.memory_limit_mb,
            "options": [
                {
                    "id": option.id,
                    "option_text": option.option_text,
                    "option_image_url": option.option_image_url,
                    "display_order": option.display_order,
                    "is_correct": option.is_correct,
                }
                for option in question.options
            ],
        }
