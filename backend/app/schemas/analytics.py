from __future__ import annotations

from pydantic import BaseModel, Field


class CohortCounts(BaseModel):
    """Who was admitted, and what became of them (§45)."""

    approved: int
    submitted: int
    in_progress: int

    # Approved but never started, or started and never finished. Named plainly rather
    # than "cheated" or "failed" — the platform does not know why.
    absent: int


class ScoreSummary(BaseModel):
    """All null when nobody has submitted; an average of nothing is not zero."""

    average: float | None
    highest: float | None
    lowest: float | None
    median: float | None


class DistributionBucket(BaseModel):
    label: str
    from_percent: int
    to_percent: int
    count: int


class QuestionAnalytics(BaseModel):
    """How one question performed (§46).

    ``correct``/``wrong`` only mean anything for the choice types. Written questions
    report what was awarded instead, and how many still await a mark.
    """

    exam_question_id: int
    position: int
    type: str
    question_text: str
    marks: int
    is_auto_marked: bool

    answered: int
    skipped: int
    correct: int | None = None
    wrong: int | None = None
    correct_rate: float | None = None

    average_marks: float | None = None
    awaiting_marks: int = 0


class ExamAnalytics(BaseModel):
    exam_id: int
    exam_title: str
    course_code: str
    total_marks: int

    cohort: CohortCounts
    scores: ScoreSummary

    # The passing mark is university policy, not something the platform knows, so it is
    # supplied per request and echoed back with the figures it produced.
    pass_percentage: float = Field(description="The threshold these counts were computed at.")
    passed: int
    failed: int
    pass_rate: float | None

    distribution: list[DistributionBucket]
    questions: list[QuestionAnalytics]
