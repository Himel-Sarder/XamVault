"""Publish validation (§28) and the immutability guarantee that follows it."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy import select

from app.models.exam import ExamQuestion
from app.models.question import Question
from tests.conftest import mcq_payload


def _add(client, api, headers, exam_id, **kwargs):
    response = client.post(
        f"{api}/exams/{exam_id}/questions", headers=headers, json=mcq_payload(**kwargs)
    )
    assert response.status_code == 201, response.text
    return response.json()


def _issues(response) -> set[str]:
    return {issue["field"] for issue in response.json()["issues"]}


def test_publish_check_reports_every_problem_at_once(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    # No questions and no start time: the teacher should see both, not one at a time.
    exam = make_exam(teacher, teacher_course, start_at=None)
    response = client.get(f"{api}/exams/{exam.id}/publish-check", headers=auth_headers(teacher))

    assert response.status_code == 200
    body = response.json()
    assert body["can_publish"] is False
    assert {issue["field"] for issue in body["issues"]} == {"questions", "start_at"}


def test_an_exam_without_questions_cannot_be_published(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    exam = make_exam(teacher, teacher_course)
    response = client.post(f"{api}/exams/{exam.id}/publish", headers=auth_headers(teacher))

    assert response.status_code == 422
    assert "questions" in _issues(response)
    still = client.get(f"{api}/exams/{exam.id}", headers=auth_headers(teacher)).json()
    assert still["status"] == "draft"


def test_an_exam_without_a_start_time_cannot_be_published(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    exam = make_exam(teacher, teacher_course, start_at=None)
    _add(client, api, auth_headers(teacher), exam.id)

    response = client.post(f"{api}/exams/{exam.id}/publish", headers=auth_headers(teacher))
    assert response.status_code == 422
    assert "start_at" in _issues(response)


def test_an_exam_whose_window_has_already_passed_cannot_be_published(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    past = datetime.now(UTC) - timedelta(days=2)
    exam = make_exam(teacher, teacher_course, start_at=past, duration_minutes=30)
    _add(client, api, auth_headers(teacher), exam.id)

    response = client.post(f"{api}/exams/{exam.id}/publish", headers=auth_headers(teacher))
    assert response.status_code == 422
    assert "start_at" in _issues(response)


def test_publishing_sets_the_window_and_totals(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    start = datetime.now(UTC) + timedelta(days=1)
    exam = make_exam(teacher, teacher_course, start_at=start, duration_minutes=45)
    headers = auth_headers(teacher)
    _add(client, api, headers, exam.id, text="Q1", marks=4)
    _add(client, api, headers, exam.id, text="Q2", marks=6)

    check = client.get(f"{api}/exams/{exam.id}/publish-check", headers=headers).json()
    assert check["can_publish"] is True

    response = client.post(f"{api}/exams/{exam.id}/publish", headers=headers)
    assert response.status_code == 200
    body = response.json()

    assert body["status"] == "published"
    assert body["published_at"] is not None
    assert body["total_marks"] == 10
    # expires_at is derived server-side from start_at + duration; clients never send it.
    expires = datetime.fromisoformat(body["expires_at"])
    starts = datetime.fromisoformat(body["start_at"])
    assert expires - starts == timedelta(minutes=45)


def test_publishing_freezes_every_question(
    client, api, auth_headers, teacher, teacher_course, make_exam, db
):
    exam = make_exam(teacher, teacher_course)
    headers = auth_headers(teacher)
    _add(client, api, headers, exam.id, text="Original wording", marks=3)
    client.post(f"{api}/exams/{exam.id}/publish", headers=headers)

    questions = client.get(f"{api}/exams/{exam.id}/questions", headers=headers).json()
    assert all(item["is_frozen"] for item in questions)

    link = db.execute(select(ExamQuestion).where(ExamQuestion.exam_id == exam.id)).scalar_one()
    snapshot = link.question_snapshot
    assert snapshot["question_text"] == "Original wording"
    assert snapshot["marks"] == 3
    # The answer key travels with the snapshot: grading must score against what the
    # student actually saw, not a question that may have been edited since.
    assert sum(1 for option in snapshot["options"] if option["is_correct"]) == 1


def test_editing_the_underlying_question_cannot_change_a_published_exam(
    client, api, auth_headers, teacher, teacher_course, make_exam, db
):
    exam = make_exam(teacher, teacher_course)
    headers = auth_headers(teacher)
    _add(client, api, headers, exam.id, text="Original wording")
    client.post(f"{api}/exams/{exam.id}/publish", headers=headers)

    # The Phase 6 question bank will allow exactly this, since one question can be
    # reused across exams. A published exam must not follow the edit.
    question = db.execute(select(Question)).scalars().first()
    question.question_text = "Tampered wording"
    db.commit()

    link = db.execute(select(ExamQuestion).where(ExamQuestion.exam_id == exam.id)).scalar_one()
    assert link.question_snapshot["question_text"] == "Original wording"


def test_a_published_exam_is_frozen_against_every_edit(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    exam = make_exam(teacher, teacher_course)
    headers = auth_headers(teacher)
    link_id = _add(client, api, headers, exam.id)["id"]
    assert client.post(f"{api}/exams/{exam.id}/publish", headers=headers).status_code == 200

    assert client.patch(
        f"{api}/exams/{exam.id}", headers=headers, json={"title": "Changed"}
    ).status_code == 409
    assert client.put(
        f"{api}/exams/{exam.id}/settings", headers=headers, json={"shuffle_questions": True}
    ).status_code == 409
    assert client.post(
        f"{api}/exams/{exam.id}/questions", headers=headers, json=mcq_payload(text="Late")
    ).status_code == 409
    assert client.put(
        f"{api}/exams/{exam.id}/questions/{link_id}", headers=headers, json=mcq_payload()
    ).status_code == 409
    assert client.delete(
        f"{api}/exams/{exam.id}/questions/{link_id}", headers=headers
    ).status_code == 409

    # Removing the exam entirely is not an edit to a frozen paper, and is governed by
    # whether anyone has sat it rather than by status -- see test_exams.py. Publishing
    # freezes the questions; it does not commit a teacher to keeping a mistake forever.
    assert client.delete(f"{api}/exams/{exam.id}", headers=headers).status_code == 204


def test_publishing_twice_is_refused(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    exam = make_exam(teacher, teacher_course)
    headers = auth_headers(teacher)
    _add(client, api, headers, exam.id)

    assert client.post(f"{api}/exams/{exam.id}/publish", headers=headers).status_code == 200
    second = client.post(f"{api}/exams/{exam.id}/publish", headers=headers)
    assert second.status_code == 409
    assert second.json()["code"] == "already_published"


def test_another_teacher_cannot_publish_my_exam(
    client, api, auth_headers, teacher, other_teacher, teacher_course, make_exam
):
    exam = make_exam(teacher, teacher_course)
    _add(client, api, auth_headers(teacher), exam.id)

    assert client.post(
        f"{api}/exams/{exam.id}/publish", headers=auth_headers(other_teacher)
    ).status_code == 404
    assert client.get(
        f"{api}/exams/{exam.id}/publish-check", headers=auth_headers(other_teacher)
    ).status_code == 404
    still = client.get(f"{api}/exams/{exam.id}", headers=auth_headers(teacher)).json()
    assert still["status"] == "draft"


def test_an_archived_course_blocks_publishing(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    exam = make_exam(teacher, teacher_course)
    headers = auth_headers(teacher)
    _add(client, api, headers, exam.id)
    client.patch(
        f"{api}/courses/{teacher_course.id}", headers=headers, json={"is_active": False}
    )

    response = client.post(f"{api}/exams/{exam.id}/publish", headers=headers)
    assert response.status_code == 422
    assert "course" in _issues(response)


def test_a_question_that_lost_its_answer_key_blocks_publishing(
    client, api, auth_headers, teacher, teacher_course, make_exam, db
):
    # The API cannot create this state, but a direct edit or a future import could.
    exam = make_exam(teacher, teacher_course)
    headers = auth_headers(teacher)
    _add(client, api, headers, exam.id)

    question = db.execute(select(Question)).scalars().one()
    for option in question.options:
        option.is_correct = False
    db.commit()

    response = client.post(f"{api}/exams/{exam.id}/publish", headers=headers)
    assert response.status_code == 422
    assert "questions" in _issues(response)
