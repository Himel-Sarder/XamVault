"""Result visibility (§44) and the teacher's release of marks."""

from __future__ import annotations

import pytest
from sqlalchemy import select

from app.models.exam import ExamQuestion


def _sit_and_submit(client, api, auth_headers, student, exam, db, *, correct: bool = True):
    headers = auth_headers(student)
    attempt = client.post(f"{api}/exams/{exam.id}/start", headers=headers).json()
    link = db.execute(
        select(ExamQuestion).where(ExamQuestion.exam_id == exam.id)
    ).scalars().first()
    option = next(
        item["id"]
        for item in link.question_snapshot["options"]
        if item["is_correct"] is correct
    )
    client.post(
        f"{api}/attempts/{attempt['id']}/answers",
        headers=headers,
        json={
            "exam_question_id": attempt["questions"][0]["exam_question_id"],
            "selected_option_id": option,
        },
    )
    return client.post(f"{api}/attempts/{attempt['id']}/submit", headers=headers).json()


def test_a_result_is_withheld_until_the_teacher_releases_it(
    client, api, auth_headers, teacher, student, approved_exam, db
):
    submitted = _sit_and_submit(client, api, auth_headers, student, approved_exam, db)
    headers = auth_headers(student)

    # Nothing is revealed by the submission itself.
    assert submitted["result_id"] is None
    assert client.get(f"{api}/results", headers=headers).json() == []

    # ...but the teacher can already see it.
    teacher_view = client.get(
        f"{api}/exams/{approved_exam.id}/results", headers=auth_headers(teacher)
    ).json()
    assert len(teacher_view) == 1
    assert teacher_view[0]["status"] == "pending"
    assert teacher_view[0]["total_score"] == 5.0
    assert teacher_view[0]["student"]["user_id"] == student.user_id

    response = client.post(
        f"{api}/exams/{approved_exam.id}/results/publish", headers=auth_headers(teacher)
    )
    assert response.json() == {"published": 1}
    assert len(client.get(f"{api}/results", headers=headers).json()) == 1


def test_show_result_immediately_skips_the_wait(
    client, api, auth_headers, teacher, student, make_approved_exam, db
):
    exam = make_approved_exam(teacher, student, show_result_immediately=True)
    submitted = _sit_and_submit(client, api, auth_headers, student, exam, db)

    assert submitted["result_id"] is not None
    results = client.get(f"{api}/results", headers=auth_headers(student)).json()
    assert results[0]["status"] == "published"
    assert results[0]["total_score"] == 5.0


def test_a_student_cannot_read_another_students_result(
    client, api, auth_headers, teacher, student, other_student, approved_exam, db
):
    _sit_and_submit(client, api, auth_headers, student, approved_exam, db)
    client.post(f"{api}/exams/{approved_exam.id}/results/publish", headers=auth_headers(teacher))
    result_id = client.get(f"{api}/results", headers=auth_headers(student)).json()[0]["id"]

    assert client.get(
        f"{api}/results/{result_id}", headers=auth_headers(other_student)
    ).status_code == 404


def test_an_unpublished_result_is_not_readable_even_by_its_owner(
    client, api, auth_headers, student, approved_exam, db
):
    _sit_and_submit(client, api, auth_headers, student, approved_exam, db)
    # The id is guessed here; the point is that no id is readable while pending.
    for candidate in range(1, 5):
        assert client.get(
            f"{api}/results/{candidate}", headers=auth_headers(student)
        ).status_code == 404


def test_another_teacher_cannot_see_or_release_my_results(
    client, api, auth_headers, other_teacher, student, approved_exam, db
):
    _sit_and_submit(client, api, auth_headers, student, approved_exam, db)
    headers = auth_headers(other_teacher)

    assert client.get(f"{api}/exams/{approved_exam.id}/results", headers=headers).status_code == 404
    assert client.post(
        f"{api}/exams/{approved_exam.id}/results/publish", headers=headers
    ).status_code == 404


def test_students_cannot_use_the_teacher_result_routes(
    client, api, auth_headers, student, approved_exam
):
    headers = auth_headers(student)
    assert client.get(f"{api}/exams/{approved_exam.id}/results", headers=headers).status_code == 403
    assert client.post(
        f"{api}/exams/{approved_exam.id}/results/publish", headers=headers
    ).status_code == 403


def test_releasing_twice_reports_nothing_left_to_do(
    client, api, auth_headers, teacher, student, approved_exam, db
):
    _sit_and_submit(client, api, auth_headers, student, approved_exam, db)
    headers = auth_headers(teacher)

    assert client.post(
        f"{api}/exams/{approved_exam.id}/results/publish", headers=headers
    ).status_code == 200
    second = client.post(f"{api}/exams/{approved_exam.id}/results/publish", headers=headers)
    assert second.status_code == 409
    assert second.json()["code"] == "nothing_to_publish"


@pytest.mark.parametrize("correct,expected", [(True, 100.0), (False, 0.0)])
def test_the_percentage_is_computed_from_the_exam_total(
    client, api, auth_headers, teacher, student, make_approved_exam, db, correct, expected
):
    exam = make_approved_exam(teacher, student, show_result_immediately=True)
    _sit_and_submit(client, api, auth_headers, student, exam, db, correct=correct)

    results = client.get(f"{api}/results", headers=auth_headers(student)).json()
    assert results[0]["percentage"] == expected
    assert results[0]["total_marks"] == exam.total_marks
