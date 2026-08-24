"""Phase 7 — what a student can discover (§29)."""

from __future__ import annotations

from datetime import timedelta


def test_a_student_sees_published_exams_in_their_enrolled_courses(
    client, api, auth_headers, teacher, student, teacher_course, make_published_exam, enroll
):
    enroll(teacher_course, student)
    exam = make_published_exam(teacher, teacher_course, title="Mid Term Quiz")

    body = client.get(f"{api}/exams", headers=auth_headers(student)).json()

    assert body["total"] == 1
    item = body["items"][0]
    assert item["id"] == exam.id
    assert item["title"] == "Mid Term Quiz"
    assert item["course_code"] == teacher_course.course_code
    assert item["availability"] == "upcoming"
    assert item["join_request_status"] == "none"
    assert item["can_request_join"] is True


def test_a_student_never_sees_a_draft(
    client, api, auth_headers, teacher, student, teacher_course, make_exam, enroll
):
    enroll(teacher_course, student)
    make_exam(teacher, teacher_course, title="Still a draft")

    assert client.get(f"{api}/exams", headers=auth_headers(student)).json()["total"] == 0


def test_a_student_never_sees_a_course_they_are_not_enrolled_in(
    client, api, auth_headers, teacher, student, teacher_course, make_published_exam
):
    make_published_exam(teacher, teacher_course)
    assert client.get(f"{api}/exams", headers=auth_headers(student)).json()["total"] == 0


def test_only_the_enrolled_student_sees_the_exam(
    client, api, auth_headers, teacher, student, other_student, teacher_course,
    make_published_exam, enroll,
):
    enroll(teacher_course, student)
    make_published_exam(teacher, teacher_course)

    assert client.get(f"{api}/exams", headers=auth_headers(student)).json()["total"] == 1
    assert client.get(f"{api}/exams", headers=auth_headers(other_student)).json()["total"] == 0


def test_a_finished_exam_is_hidden_unless_asked_for(
    client, api, auth_headers, teacher, student, teacher_course, make_published_exam, enroll
):
    enroll(teacher_course, student)
    make_published_exam(teacher, teacher_course, starts_in=timedelta(days=-2))
    headers = auth_headers(student)

    assert client.get(f"{api}/exams", headers=headers).json()["total"] == 0

    body = client.get(f"{api}/exams", headers=headers, params={"include_closed": True}).json()
    assert body["total"] == 1
    assert body["items"][0]["availability"] == "closed"
    assert body["items"][0]["can_request_join"] is False


def test_availability_reflects_the_server_clock(
    client, api, auth_headers, teacher, student, teacher_course, make_published_exam, enroll
):
    enroll(teacher_course, student)
    # Started ten minutes ago, runs for 30: the window is open right now.
    make_published_exam(
        teacher, teacher_course, starts_in=timedelta(minutes=-10), duration_minutes=30
    )
    body = client.get(f"{api}/exams", headers=auth_headers(student)).json()
    assert body["items"][0]["availability"] == "open"


def test_the_student_view_carries_no_teacher_fields_and_no_answer_key(
    client, api, auth_headers, teacher, student, teacher_course, make_published_exam, enroll
):
    enroll(teacher_course, student)
    exam = make_published_exam(teacher, teacher_course)

    response = client.get(f"{api}/exams/{exam.id}", headers=auth_headers(student))
    assert response.status_code == 200
    body = response.json()

    for leaked in ("teacher_id", "published_at", "status"):
        assert leaked not in body, f"{leaked} must not reach a student"
    assert "is_correct" not in response.text
    # Only the settings a student needs are present.
    assert set(body["settings"]) == {"secure_mode", "allow_back_navigation", "max_attempts"}
    assert body["question_count"] == 1
    assert body["total_marks"] == 5


def test_the_teacher_still_gets_the_teacher_view(
    client, api, auth_headers, teacher, teacher_course, make_published_exam
):
    exam = make_published_exam(teacher, teacher_course)
    body = client.get(f"{api}/exams/{exam.id}", headers=auth_headers(teacher)).json()

    assert body["teacher_id"] == teacher.id
    assert body["status"] == "published"
    assert "availability" not in body


def test_a_student_cannot_read_an_exam_they_have_no_access_to(
    client, api, auth_headers, teacher, student, teacher_course, make_exam, make_published_exam
):
    draft = make_exam(teacher, teacher_course)
    published_but_unenrolled = make_published_exam(teacher, teacher_course)
    headers = auth_headers(student)

    assert client.get(f"{api}/exams/{draft.id}", headers=headers).status_code == 404
    assert client.get(
        f"{api}/exams/{published_but_unenrolled.id}", headers=headers
    ).status_code == 404


def test_a_student_cannot_use_the_teacher_write_routes(
    client, api, auth_headers, teacher, student, teacher_course, make_published_exam, enroll
):
    enroll(teacher_course, student)
    exam = make_published_exam(teacher, teacher_course)
    headers = auth_headers(student)

    assert client.patch(f"{api}/exams/{exam.id}", headers=headers, json={"title": "x"}).status_code == 403
    assert client.post(f"{api}/exams/{exam.id}/publish", headers=headers).status_code == 403
    assert client.get(f"{api}/exams/{exam.id}/questions", headers=headers).status_code == 403
    assert client.get(f"{api}/exams/{exam.id}/join-requests", headers=headers).status_code == 403
