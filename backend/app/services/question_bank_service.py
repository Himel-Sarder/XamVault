"""Phase 6 — the reusable question library (§6).

A question already lives independently of any exam; ``exam_questions`` is only the link.
This service exposes that library directly, so a teacher can build a question once and
use it across terms.

What makes reuse safe is the snapshot taken at publish: a published exam renders and
grades from its own frozen copy, so editing a question here can never disturb a paper
students have already sat. A *draft* exam does follow the edit, which is what a teacher
would expect.
"""

from __future__ import annotations

from sqlalchemy.orm import Session

from app.core.exceptions import ConflictError, InvalidRequestError, NotFoundError
from app.models.enums import EDITABLE_EXAM_STATUSES, QuestionType
from app.models.exam import ExamQuestion
from app.models.question import Question, QuestionOption
from app.models.user import User
from app.repositories.exam_repository import ExamRepository
from app.repositories.question_repository import QuestionRepository
from app.schemas.question import QuestionCreate
from app.schemas.question_bank import BankQuestionResponse


class QuestionBankService:
    def __init__(self, db: Session) -> None:
        self.db = db
        self.questions = QuestionRepository(db)
        self.exams = ExamRepository(db)

    # --------------------------------------------------------- authorization

    @staticmethod
    def _scope(actor: User) -> int | None:
        """An admin sees every question; a teacher sees only their own."""
        return None if actor.is_admin else actor.id

    def _owned(self, question_id: int, actor: User) -> Question:
        question = self.questions.get(question_id)
        if question is None:
            raise NotFoundError("Question not found")
        if actor.is_admin or question.created_by == actor.id:
            return question
        # 404 rather than 403: another teacher's question is not theirs to know about.
        raise NotFoundError("Question not found")

    # ----------------------------------------------------------------- reads

    def list_questions(
        self,
        actor: User,
        *,
        question_type: str | None,
        difficulty: str | None,
        topic: str | None,
        search: str | None,
        offset: int,
        limit: int,
    ) -> tuple[list[BankQuestionResponse], int]:
        if question_type is not None and question_type not in tuple(QuestionType):
            raise InvalidRequestError(f"Unknown question type '{question_type}'")

        rows, total = self.questions.list_bank(
            self._scope(actor),
            question_type=question_type,
            difficulty=difficulty,
            topic=topic,
            search=search,
            offset=offset,
            limit=limit,
        )
        # One usage query for the whole page rather than one per question.
        usage = self.questions.usage([question.id for question in rows])
        return [self._present(question, usage) for question in rows], total

    def get(self, question_id: int, actor: User) -> BankQuestionResponse:
        question = self._owned(question_id, actor)
        return self._present(question, self.questions.usage([question.id]))

    def topics(self, actor: User) -> list[str]:
        return self.questions.topics_for(self._scope(actor))

    # ---------------------------------------------------------------- writes

    def create(self, data: QuestionCreate, actor: User) -> BankQuestionResponse:
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
        self.db.commit()
        return self.get(question.id, actor)

    def update(self, question_id: int, data: QuestionCreate, actor: User) -> BankQuestionResponse:
        question = self._owned(question_id, actor)

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

        # Draft exams follow the edit, so their totals must follow it too. Published
        # exams are untouched: they render from their own frozen snapshot.
        drafts = [
            link for link in question.exam_links
            if link.exam.status in EDITABLE_EXAM_STATUSES
        ]
        for link in drafts:
            link.marks_snapshot = data.marks
        self.db.flush()
        for link in drafts:
            link.exam.total_marks = self.exams.sum_marks(link.exam_id)

        self.db.commit()
        return self.get(question.id, actor)

    def delete(self, question_id: int, actor: User) -> None:
        question = self._owned(question_id, actor)
        if question.exam_links:
            raise ConflictError(
                "This question is used by an exam. Remove it from the exam first.",
                code="question_in_use",
            )
        self.questions.delete(question)
        self.db.commit()

    # ------------------------------------------------------------- attaching

    def attach_to_exam(
        self, exam_id: int, question_ids: list[int], actor: User
    ) -> list[ExamQuestion]:
        exam = self.exams.get(exam_id)
        if exam is None or not (actor.is_admin or exam.teacher_id == actor.id):
            raise NotFoundError("Exam not found")
        if exam.status not in EDITABLE_EXAM_STATUSES:
            raise ConflictError(
                f"This exam is {exam.status} and can no longer be edited.",
                code="exam_not_editable",
            )

        existing = {link.question_id for link in self.exams.list_exam_questions(exam.id)}
        added: list[ExamQuestion] = []
        for question_id in question_ids:
            question = self._owned(question_id, actor)
            if question.id in existing:
                # Skipping silently would leave the teacher wondering why the count did
                # not move; the same question twice in one paper is a mistake, not a
                # preference.
                raise ConflictError(
                    f"Question {question.id} is already in this exam",
                    code="already_attached",
                )
            added.append(
                self.exams.add_exam_question(
                    ExamQuestion(
                        exam_id=exam.id,
                        question_id=question.id,
                        marks_snapshot=question.marks,
                        display_order=self.exams.next_display_order(exam.id),
                    )
                )
            )
            existing.add(question.id)

        self.db.flush()
        exam.total_marks = self.exams.sum_marks(exam.id)
        self.db.commit()
        return added

    # --------------------------------------------------------------- shaping

    @staticmethod
    def _present(
        question: Question, usage: dict[int, tuple[int, bool]]
    ) -> BankQuestionResponse:
        count, published = usage.get(question.id, (0, False))
        return BankQuestionResponse(
            id=question.id,
            type=question.type,
            question_text=question.question_text,
            question_image_url=question.question_image_url,
            marks=question.marks,
            difficulty=question.difficulty,
            topic=question.topic,
            language=question.language,
            time_limit_seconds=question.time_limit_seconds,
            memory_limit_mb=question.memory_limit_mb,
            created_at=question.created_at,
            options=[
                {
                    "id": option.id,
                    "option_text": option.option_text,
                    "option_image_url": option.option_image_url,
                    "display_order": option.display_order,
                    "is_correct": option.is_correct,
                }
                for option in question.options
            ],
            used_in_exams=count,
            used_in_published=published,
        )
