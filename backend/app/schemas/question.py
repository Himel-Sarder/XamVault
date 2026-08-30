from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, model_validator

from app.models.enums import (
    CHOICE_QUESTION_TYPES,
    IMAGE_STEM_TYPES,
    MANUAL_QUESTION_TYPES,
    QuestionType,
)
from app.schemas.common import ORMModel

QuestionTypeLiteral = Literal[
    "TEXT_MCQ",
    "IMAGE_TEXT_OPTIONS",
    "IMAGE_IMAGE_OPTIONS",
    "SHORT_ANSWER",
    "CODE_ANSWER",
]

MIN_OPTIONS = 2
MAX_OPTIONS = 8

# Languages the code editor offers. Kept small and explicit: an unbounded list would be
# a promise the sandbox (Phase 15) has to keep.
CodeLanguage = Literal["c", "cpp", "java", "python", "javascript"]


class QuestionOptionCreate(BaseModel):
    """``option_text`` for text options, ``option_image_url`` for image options; the
    per-type validation below decides which is required."""

    option_text: str | None = Field(default=None, max_length=1000)
    option_image_url: str | None = Field(default=None, max_length=500)
    is_correct: bool = False


class QuestionOptionResponse(ORMModel):
    """Teacher-facing. Includes the answer key."""

    id: int
    option_text: str | None
    option_image_url: str | None
    display_order: int
    is_correct: bool


class QuestionCreate(BaseModel):
    """``created_by``, ``id`` and ordering are server-assigned and absent here.

    Validation is per type rather than one-size-fits-all: a short answer has no options
    to check, and an image question is useless without its image.
    """

    type: QuestionTypeLiteral = QuestionType.TEXT_MCQ.value
    question_text: str = Field(min_length=1, max_length=5000)
    question_image_url: str | None = Field(default=None, max_length=500)
    marks: int = Field(default=1, ge=1, le=100)
    difficulty: Literal["easy", "medium", "hard"] | None = None
    topic: str | None = Field(default=None, max_length=150)
    options: list[QuestionOptionCreate] = Field(default_factory=list, max_length=MAX_OPTIONS)

    # CODE_ANSWER only.
    language: CodeLanguage | None = None
    time_limit_seconds: int | None = Field(default=None, ge=1, le=30)
    memory_limit_mb: int | None = Field(default=None, ge=16, le=1024)

    @model_validator(mode="after")
    def _validate_for_type(self) -> "QuestionCreate":
        if self.type in CHOICE_QUESTION_TYPES:
            self._validate_choice_question()
        else:
            self._validate_written_question()

        if self.type in IMAGE_STEM_TYPES and not self.question_image_url:
            raise ValueError("This question type needs an image for the question itself")

        if self.type == QuestionType.CODE_ANSWER and not self.language:
            raise ValueError("Choose the language students must answer in")
        if self.type != QuestionType.CODE_ANSWER and self.language:
            raise ValueError("Only code questions take a language")
        return self

    def _validate_choice_question(self) -> None:
        if not (MIN_OPTIONS <= len(self.options) <= MAX_OPTIONS):
            raise ValueError(
                f"A multiple-choice question needs between {MIN_OPTIONS} and "
                f"{MAX_OPTIONS} options"
            )

        correct = sum(1 for option in self.options if option.is_correct)
        if correct == 0:
            raise ValueError("Mark one option as the correct answer")
        if correct > 1:
            raise ValueError("A multiple-choice question must have exactly one correct answer")

        if self.type == QuestionType.IMAGE_IMAGE_OPTIONS:
            if any(not option.option_image_url for option in self.options):
                raise ValueError("Every option of this question type needs an image")
            keys = [option.option_image_url for option in self.options]
        else:
            if any(not (option.option_text or "").strip() for option in self.options):
                raise ValueError("Every option needs text")
            keys = [(option.option_text or "").strip().lower() for option in self.options]

        if len(set(keys)) != len(keys):
            raise ValueError("Options must be different from one another")

    def _validate_written_question(self) -> None:
        if self.options:
            raise ValueError("This question type is answered in writing, not by choosing")


class QuestionUpdate(QuestionCreate):
    """Same shape as create: an edit replaces the question wholesale.

    Patching individual options would need stable client-side option ids and gains
    nothing here - a question is small, and replacing it keeps the per-type rules
    enforceable in one place.
    """


class TeacherQuestionResponse(ORMModel):
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
    created_by: int
    created_at: datetime
    options: list[QuestionOptionResponse]

    @property
    def is_manually_graded(self) -> bool:
        return self.type in MANUAL_QUESTION_TYPES


class ExamQuestionResponse(ORMModel):
    """A question as it sits inside an exam."""

    id: int
    exam_id: int
    display_order: int
    marks_snapshot: int
    is_frozen: bool
    question: TeacherQuestionResponse


class UploadedImageResponse(BaseModel):
    url: str
    width: int
    height: int
    bytes: int
