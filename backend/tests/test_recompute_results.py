"""Rebuilding stored results after the aggregation was fixed.

A result is written when an attempt is submitted and again after every manual mark, so a
bug in the aggregation is baked into every row it touched. Fixing the aggregation does
not go back for those rows -- their numbers only move when somebody marks that attempt
again, which for a finished exam nobody will.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from decimal import Decimal

import pytest

from app.models.result import Result
from app.utils.recompute_results import recompute_results
from tests.conftest import png_bytes


@pytest.fixture
def marked_exam(
    client, api, auth_headers, teacher, teacher_course, student, enroll,
    make_exam, make_join_request, db,
):
    """A photo question worth 1 and a code question worth 5, both sat and both marked.

    The shape that exposed the bug: a paper of two kinds, where one kind was dropped
    from the total and the other was not.
    """
    enroll(teacher_course, student)
    exam = make_exam(
        teacher, teacher_course, start_at=datetime.now(UTC) - timedelta(minutes=1)
    )
    headers = auth_headers(teacher)
    for payload in (
        {"type": "PHOTO_ANSWER", "question_text": "Photograph your working.", "marks": 1},
        {"type": "CODE_ANSWER", "question_text": "Write it.", "marks": 5,
         "language": "python"},
    ):
        assert client.post(
            f"{api}/exams/{exam.id}/questions", headers=headers, json=payload
        ).status_code == 201

    assert client.post(f"{api}/exams/{exam.id}/publish", headers=headers).status_code == 200
    make_join_request(exam, student, status="approved")

    student_headers = auth_headers(student)
    attempt = client.post(f"{api}/exams/{exam.id}/start", headers=student_headers).json()
    by_type = {q["type"]: q["exam_question_id"] for q in attempt["questions"]}

    client.post(
        f"{api}/attempts/{attempt['id']}/answers/{by_type['PHOTO_ANSWER']}/photos",
        headers=student_headers,
        files={"file": ("page.png", png_bytes(), "image/png")},
    )
    client.post(
        f"{api}/attempts/{attempt['id']}/answers",
        headers=student_headers,
        json={"exam_question_id": by_type["CODE_ANSWER"], "answer_text": "def f(): pass"},
    )
    client.post(f"{api}/attempts/{attempt['id']}/submit", headers=student_headers)

    queue = client.get(f"{api}/attempts/{attempt['id']}/grading", headers=headers).json()
    for wanted, marks in (("CODE_ANSWER", 4), ("PHOTO_ANSWER", 1)):
        entry = next(a for a in queue["answers"] if a["type"] == wanted)
        client.post(
            f"{api}/attempts/{attempt['id']}/answers/{entry['answer_id']}/evaluate",
            headers=headers,
            json={"marks_awarded": marks},
        )

    db.expunge_all()
    result = db.query(Result).filter(Result.exam_id == exam.id).one()
    assert Decimal(str(result.total_score)) == Decimal("5")
    return result.id


def _as_the_old_code_wrote_it(db, result_id: int) -> None:
    """The photograph's mark added to nothing: total 4 instead of 5."""
    result = db.get(Result, result_id)
    result.short_answer_score = Decimal("0")
    result.total_score = Decimal("4")
    db.commit()
    db.expunge_all()


def _stored_total(db, result_id: int) -> Decimal:
    db.expunge_all()
    return Decimal(str(db.get(Result, result_id).total_score))


def test_a_dry_run_reports_without_writing(db, marked_exam):
    _as_the_old_code_wrote_it(db, marked_exam)

    corrections = recompute_results(db, commit=False)

    assert [c.result_id for c in corrections] == [marked_exam]
    assert corrections[0].before == Decimal("4")
    assert corrections[0].after == Decimal("5")
    assert corrections[0].difference == Decimal("1")
    assert _stored_total(db, marked_exam) == Decimal("4"), "a dry run must write nothing"


def test_committing_corrects_the_stored_total(db, marked_exam):
    _as_the_old_code_wrote_it(db, marked_exam)

    assert len(recompute_results(db, commit=True)) == 1

    assert _stored_total(db, marked_exam) == Decimal("5")


def test_running_it_twice_reports_nothing_the_second_time(db, marked_exam):
    _as_the_old_code_wrote_it(db, marked_exam)
    assert len(recompute_results(db, commit=True)) == 1

    assert recompute_results(db, commit=True) == []


def test_a_released_result_stays_released(db, marked_exam):
    """The student has already been shown this. Correcting it must not hide it again."""
    result = db.get(Result, marked_exam)
    result.status = "published"
    result.published_at = datetime.now(UTC)
    db.commit()
    _as_the_old_code_wrote_it(db, marked_exam)

    recompute_results(db, commit=True)

    db.expunge_all()
    assert db.get(Result, marked_exam).status == "published"
