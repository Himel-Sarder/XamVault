from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

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
