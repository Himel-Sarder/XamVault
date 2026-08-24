"""Submission, MCQ grading and results (§41-§44)."""

from __future__ import annotations

from datetime import timedelta

import pytest
from sqlalchemy import select

from app.models.exam import ExamQuestion


@pytest.fixture
def sitting(client, api, auth_headers, student, approved_exam, db):
    """An attempt in progress, plus the correct option id taken from the frozen snapshot."""
    headers = auth_headers(student)
    attempt = client.post(
        f"{api}/exams/{approved_exam.id}/start", headers=headers
    ).json()

    link = db.execute(
        select(ExamQuestion).where(ExamQuestion.exam_id == approved_exam.id)
    ).scalars().first()
    correct = next(
        option["id"] for option in link.question_snapshot["options"] if option["is_correct"]
    )
    wrong = next(
        option["id"] for option in link.question_snapshot["options"] if not option["is_correct"]
    )
    return {"attempt": attempt, "correct": correct, "wrong": wrong, "exam": approved_exam}


def _publish_results(client, api, auth_headers, teacher, exam_id):
    """A teacher releasing the marks. Results are withheld until this happens, unless
    the exam is configured to show them immediately."""
    response = client.post(
        f"{api}/exams/{exam_id}/results/publish", headers=auth_headers(teacher)
    )
    assert response.status_code == 200, response.text
    return response.json()


def _answer(client, api, headers, attempt, option_id):
    return client.post(
        f"{api}/attempts/{attempt['id']}/answers",
        headers=headers,
        json={
            "exam_question_id": attempt["questions"][0]["exam_question_id"],
            "selected_option_id": option_id,
        },
    )


def test_a_correct_answer_scores_full_marks(client, api, auth_headers, teacher, student, sitting):
    headers = auth_headers(student)
    attempt = sitting["attempt"]
    _answer(client, api, headers, attempt, sitting["correct"])

    response = client.post(f"{api}/attempts/{attempt['id']}/submit", headers=headers)
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "submitted"
    assert body["answered_count"] == 1
    assert body["total_questions"] == 1

    _publish_results(client, api, auth_headers, teacher, sitting["exam"].id)
    results = client.get(f"{api}/results", headers=headers).json()
    assert len(results) == 1
    assert results[0]["total_score"] == 5.0
    assert results[0]["percentage"] == 100.0
    assert results[0]["scores"]["mcq"] == 5.0


def test_a_wrong_answer_scores_nothing(client, api, auth_headers, teacher, student, sitting):
    headers = auth_headers(student)
    attempt = sitting["attempt"]
    _answer(client, api, headers, attempt, sitting["wrong"])
    client.post(f"{api}/attempts/{attempt['id']}/submit", headers=headers)

    _publish_results(client, api, auth_headers, teacher, sitting["exam"].id)
    results = client.get(f"{api}/results", headers=headers).json()
    assert results[0]["total_score"] == 0.0
    assert results[0]["percentage"] == 0.0


def test_an_unanswered_question_scores_nothing(client, api, auth_headers, teacher, student, sitting):
    headers = auth_headers(student)
    client.post(f"{api}/attempts/{sitting['attempt']['id']}/submit", headers=headers)

    _publish_results(client, api, auth_headers, teacher, sitting["exam"].id)
    results = client.get(f"{api}/results", headers=headers).json()
    assert results[0]["total_score"] == 0.0


def test_submitting_twice_is_refused(client, api, auth_headers, student, sitting):
    headers = auth_headers(student)
    attempt_id = sitting["attempt"]["id"]

    assert client.post(f"{api}/attempts/{attempt_id}/submit", headers=headers).status_code == 200
    second = client.post(f"{api}/attempts/{attempt_id}/submit", headers=headers)
    assert second.status_code == 409
    assert second.json()["code"] == "already_submitted"


def test_a_submitted_attempt_is_frozen(client, api, auth_headers, teacher, student, sitting):
    headers = auth_headers(student)
    attempt = sitting["attempt"]
    _answer(client, api, headers, attempt, sitting["wrong"])
    client.post(f"{api}/attempts/{attempt['id']}/submit", headers=headers)

    # Changing an answer after submitting must not be possible (§40).
    late = _answer(client, api, headers, attempt, sitting["correct"])
    assert late.status_code == 409

    _publish_results(client, api, auth_headers, teacher, sitting["exam"].id)
    results = client.get(f"{api}/results", headers=headers).json()
    assert results[0]["total_score"] == 0.0, "the late change must not have counted"


def test_submitting_after_the_deadline_is_recorded_as_auto_submitted(
    client, api, auth_headers, teacher, student, sitting, expire_attempt
):
    headers = auth_headers(student)
    attempt = sitting["attempt"]
    _answer(client, api, headers, attempt, sitting["correct"])
    expire_attempt(attempt["id"])

    response = client.post(f"{api}/attempts/{attempt['id']}/submit", headers=headers)
    assert response.status_code == 200
    assert response.json()["status"] == "auto_submitted"

    # The answers given before time ran out still count.
    _publish_results(client, api, auth_headers, teacher, sitting["exam"].id)
    assert client.get(f"{api}/results", headers=headers).json()[0]["total_score"] == 5.0


def test_grading_uses_the_snapshot_not_the_live_question(
    client, api, auth_headers, teacher, student, sitting, db
):
    from app.models.question import Question

    headers = auth_headers(student)
    attempt = sitting["attempt"]
    _answer(client, api, headers, attempt, sitting["correct"])

    # Move the answer key on the live question, as a later edit or import could.
    question = db.execute(select(Question)).scalars().first()
    for option in question.options:
        option.is_correct = not option.is_correct
    db.commit()

    client.post(f"{api}/attempts/{attempt['id']}/submit", headers=headers)
    _publish_results(client, api, auth_headers, teacher, sitting["exam"].id)
    results = client.get(f"{api}/results", headers=headers).json()
    assert results[0]["total_score"] == 5.0, "the mark must follow the frozen snapshot"
