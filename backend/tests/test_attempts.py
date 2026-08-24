"""Phase 9-11 — starting an exam, the server-owned clock, and randomisation."""

from __future__ import annotations

from datetime import timedelta


def _start(client, api, headers, exam_id):
    return client.post(f"{api}/exams/{exam_id}/start", headers=headers)


def test_an_approved_student_can_start(client, api, auth_headers, student, approved_exam):
    response = _start(client, api, auth_headers(student), approved_exam.id)

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "active"
    assert body["exam_id"] == approved_exam.id
    assert body["total_questions"] == 1
    assert body["answered_count"] == 0
    assert body["remaining_seconds"] > 0
    # The paper carries no answer key.
    assert "is_correct" not in response.text


def test_the_deadline_is_set_by_the_server(client, api, auth_headers, student, approved_exam):
    body = _start(client, api, auth_headers(student), approved_exam.id).json()

    from datetime import datetime

    started = datetime.fromisoformat(body["started_at"])
    expires = datetime.fromisoformat(body["expires_at"])
    # The exam started a minute ago and runs 60 minutes, so the attempt inherits the
    # exam's own window rather than a fresh 60 minutes from now.
    assert expires > started
    assert (expires - started) <= timedelta(minutes=60)
    assert body["remaining_seconds"] <= 60 * 60


def test_a_student_without_approval_cannot_start(
    client, api, auth_headers, teacher, student, teacher_course, make_published_exam, enroll
):
    enroll(teacher_course, student)
    exam = make_published_exam(
        teacher, teacher_course, starts_in=timedelta(minutes=-1), duration_minutes=60
    )
    response = _start(client, api, auth_headers(student), exam.id)

    assert response.status_code == 403
    assert response.json()["code"] == "not_approved"


def test_a_pending_request_is_not_approval(
    client, api, auth_headers, teacher, student, teacher_course,
    make_published_exam, enroll, make_join_request,
):
    enroll(teacher_course, student)
    exam = make_published_exam(
        teacher, teacher_course, starts_in=timedelta(minutes=-1), duration_minutes=60
    )
    make_join_request(exam, student, status="pending")

    assert _start(client, api, auth_headers(student), exam.id).status_code == 403


def test_a_student_who_is_not_enrolled_cannot_start(
    client, api, auth_headers, other_student, approved_exam
):
    assert _start(client, api, auth_headers(other_student), approved_exam.id).status_code == 404


def test_an_exam_that_has_not_opened_yet_cannot_be_started(
    client, api, auth_headers, teacher, student, teacher_course,
    make_published_exam, enroll, make_join_request,
):
    enroll(teacher_course, student)
    exam = make_published_exam(teacher, teacher_course, starts_in=timedelta(days=1))
    make_join_request(exam, student, status="approved")

    response = _start(client, api, auth_headers(student), exam.id)
    assert response.status_code == 409
    assert response.json()["code"] == "not_started"


def test_an_exam_that_has_ended_cannot_be_started(
    client, api, auth_headers, teacher, student, teacher_course,
    make_published_exam, enroll, make_join_request,
):
    enroll(teacher_course, student)
    exam = make_published_exam(teacher, teacher_course, starts_in=timedelta(days=-2))
    make_join_request(exam, student, status="approved")

    response = _start(client, api, auth_headers(student), exam.id)
    assert response.status_code == 409
    assert response.json()["code"] == "exam_closed"


def test_teachers_cannot_sit_exams(client, api, auth_headers, teacher, approved_exam):
    assert _start(client, api, auth_headers(teacher), approved_exam.id).status_code == 403


def test_starting_twice_resumes_the_same_attempt(
    client, api, auth_headers, student, approved_exam
):
    headers = auth_headers(student)
    first = _start(client, api, headers, approved_exam.id).json()
    second = _start(client, api, headers, approved_exam.id).json()

    # An app restart must not hand out a fresh clock or a different paper (§60).
    assert second["id"] == first["id"]
    assert second["started_at"] == first["started_at"]
    assert second["expires_at"] == first["expires_at"]
    assert [q["exam_question_id"] for q in second["questions"]] == [
        q["exam_question_id"] for q in first["questions"]
    ]


def test_max_attempts_is_enforced(
    client, api, auth_headers, student, approved_exam, expire_attempt
):
    headers = auth_headers(student)
    attempt_id = _start(client, api, headers, approved_exam.id).json()["id"]
    client.post(f"{api}/attempts/{attempt_id}/submit", headers=headers)

    second = _start(client, api, headers, approved_exam.id)
    assert second.status_code == 409
    assert second.json()["code"] == "no_attempts_left"
