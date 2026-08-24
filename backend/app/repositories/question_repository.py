from __future__ import annotations

from sqlalchemy import Select, case, func, select
from sqlalchemy.orm import Session, selectinload

from app.models.enums import ExamStatus
from app.models.exam import Exam, ExamQuestion
from app.models.question import Question, QuestionOption


class QuestionRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def get(self, question_id: int) -> Question | None:
        return self.db.execute(
            select(Question)
            .where(Question.id == question_id)
            .options(selectinload(Question.options))
        ).scalar_one_or_none()

    # ------------------------------------------------------------- the bank

    def _bank_query(self, owner_id: int | None) -> Select:
        """A teacher's own library. ``None`` means every question, for an admin."""
        stmt = select(Question)
        return stmt if owner_id is None else stmt.where(Question.created_by == owner_id)

    def list_bank(
        self,
        owner_id: int | None,
        *,
        question_type: str | None,
        difficulty: str | None,
        topic: str | None,
        search: str | None,
        offset: int,
        limit: int,
    ) -> tuple[list[Question], int]:
        base = self._bank_query(owner_id)
        if question_type:
            base = base.where(Question.type == question_type)
        if difficulty:
            base = base.where(Question.difficulty == difficulty)
        if topic:
            base = base.where(Question.topic == topic)
        if search:
            pattern = f"%{search.lower()}%"
            base = base.where(func.lower(Question.question_text).like(pattern))

        total = self.db.execute(
            select(func.count()).select_from(base.subquery())
        ).scalar_one()
        rows = (
            self.db.execute(
                base.options(selectinload(Question.options))
                .order_by(Question.created_at.desc(), Question.id.desc())
                .offset(offset)
                .limit(limit)
            )
            .scalars()
            .all()
        )
        return list(rows), total

    def topics_for(self, owner_id: int | None) -> list[str]:
        stmt = select(Question.topic).where(Question.topic.is_not(None)).distinct()
        if owner_id is not None:
            stmt = stmt.where(Question.created_by == owner_id)
        return sorted(row for row in self.db.execute(stmt).scalars().all() if row)

    def usage(self, question_ids: list[int]) -> dict[int, tuple[int, bool]]:
        """``{question_id: (exam_count, appears_in_a_published_exam)}`` in one query."""
        if not question_ids:
            return {}
        published = case((Exam.status == ExamStatus.PUBLISHED.value, 1), else_=0)
        rows = self.db.execute(
            select(
                ExamQuestion.question_id,
                func.count(ExamQuestion.id),
                func.max(published),
            )
            .join(Exam, Exam.id == ExamQuestion.exam_id)
            .where(ExamQuestion.question_id.in_(question_ids))
            .group_by(ExamQuestion.question_id)
        ).all()
        return {row[0]: (row[1], bool(row[2])) for row in rows}

    def add(self, question: Question) -> Question:
        self.db.add(question)
        self.db.flush()
        return question

    def add_option(self, option: QuestionOption) -> QuestionOption:
        self.db.add(option)
        self.db.flush()
        return option

    def replace_options(self, question: Question, options: list[QuestionOption]) -> None:
        """Swap the whole option set.

        ``delete-orphan`` on the relationship removes the old rows; assigning the list
        keeps the in-memory object consistent with the database in one step.
        """
        question.options[:] = options
        self.db.flush()

    def delete(self, question: Question) -> None:
        self.db.delete(question)
        self.db.flush()
