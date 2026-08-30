"""Rebuild stored results from the answers they were computed from.

A result is written once, when the attempt is submitted, and again after every manual
mark. That means a bug in the aggregation is baked into every row it touched, and fixing
the aggregation does not go back and correct them -- the numbers only move when somebody
marks that attempt again, which for a finished exam nobody will.

That is exactly what happened to PHOTO_ANSWER: its marks were added to no component, so
every attempt containing one has a total short by however much was awarded for it.

Dry run by default. Nothing is written unless ``commit=True``, because this rewrites
marks students have already been shown.
"""
from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.attempt import ExamAttempt
from app.models.result import Result
from app.services.attempt_service import AttemptService


@dataclass(frozen=True)
class Correction:
    """One result whose stored total did not match its answers."""

    result_id: int
    exam_id: int
    exam_title: str
    student_id: int
    before: Decimal
    after: Decimal

    @property
    def difference(self) -> Decimal:
        return self.after - self.before

    def __str__(self) -> str:  # pragma: no cover - human output
        return (
            f"result {self.result_id} (exam {self.exam_id} '{self.exam_title}', "
            f"student {self.student_id}): {self.before} -> {self.after}"
        )


def recompute_results(db: Session, *, commit: bool = False) -> list[Correction]:
    """Recompute every stored result; report the ones whose total changes.

    The recomputation is the service's own, not a copy of it. A second implementation
    of the same arithmetic would be a second thing to get wrong, and the point of this
    is to apply the version that is now correct.
    """
    service = AttemptService(db)
    corrections: list[Correction] = []

    results = db.execute(select(Result).order_by(Result.id)).scalars().all()
    for result in results:
        attempt = db.get(ExamAttempt, result.attempt_id)
        if attempt is None:  # pragma: no cover - FK makes this unreachable
            continue

        before = Decimal(str(result.total_score))
        service.recompute_result(attempt)
        after = Decimal(str(result.total_score))

        if before != after:
            corrections.append(
                Correction(
                    result_id=result.id,
                    exam_id=result.exam_id,
                    exam_title=attempt.exam.title,
                    student_id=result.student_id,
                    before=before,
                    after=after,
                )
            )

    if commit:
        db.commit()
    else:
        # recompute_result flushes, so the session holds the new values either way.
        db.rollback()

    return corrections
