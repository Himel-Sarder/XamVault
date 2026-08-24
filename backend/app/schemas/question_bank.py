from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field

from app.schemas.question import QuestionOptionResponse


class BankQuestionResponse(BaseModel):
    """A reusable question, with how widely it is already used."""

    id: int
    type: str
    question_text: str
    question_image_url: str | None
    marks: int
    difficulty: str | None
    topic: str | None
    language: str | None
    time_limit_seconds: int | None
    memory_limit_mb: int | None
    created_at: datetime
    options: list[QuestionOptionResponse]

    # How many exams link to this question, and whether any of them is published.
    # A published exam renders from its own frozen snapshot, so editing here cannot
    # disturb it — but a teacher should still be told the question is in circulation.
    used_in_exams: int
    used_in_published: bool

    @property
    def is_deletable(self) -> bool:
        return self.used_in_exams == 0


class AttachFromBankRequest(BaseModel):
    """Add existing questions to a draft exam, in the order given."""

    question_ids: list[int] = Field(min_length=1, max_length=100)


class BankTopicsResponse(BaseModel):
    """The topics this teacher has actually used, for filter chips."""

    topics: list[str]
