"""Phase 8 — join requests and teacher approval (§30, §31)."""

from __future__ import annotations

from datetime import timedelta

import pytest


@pytest.fixture
def enrolled_exam(teacher, teacher_course, student, make_published_exam, enroll):
    enroll(teacher_course, student)
    return make_published_exam(teacher, teacher_course)


def test_a_student_can_request_to_join(client, api, auth_headers, student, enrolled_exam):
    response = client.post(
        f"{api}/exams/{enrolled_exam.id}/join-request", headers=auth_headers(student)
    )
    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "pending"
    assert body["student"]["user_id"] == student.user_id
    assert body["student"]["student_number"] == student.user_id
    assert body["reviewed_at"] is None


def test_the_exam_then_reports_the_request_state(
    client, api, auth_headers, student, enrolled_exam
):
    headers = auth_headers(student)
    client.post(f"{api}/exams/{enrolled_exam.id}/join-request", headers=headers)

    body = client.get(f"{api}/exams/{enrolled_exam.id}", headers=headers).json()
    assert body["join_request_status"] == "pending"
    assert body["can_request_join"] is False, "asking twice must not be offered"


def test_a_second_pending_request_is_refused(
    client, api, auth_headers, student, enrolled_exam
):
    headers = auth_headers(student)
    url = f"{api}/exams/{enrolled_exam.id}/join-request"

    assert client.post(url, headers=headers).status_code == 201
    second = client.post(url, headers=headers)
    assert second.status_code == 409
    assert second.json()["code"] == "request_pending"


def test_a_student_cannot_request_an_exam_they_cannot_see(
    client, api, auth_headers, other_student, enrolled_exam
):
    response = client.post(
        f"{api}/exams/{enrolled_exam.id}/join-request", headers=auth_headers(other_student)
    )
    assert response.status_code == 404


def test_a_student_cannot_request_a_draft(
    client, api, auth_headers, teacher, student, teacher_course, make_exam, enroll
):
    enroll(teacher_course, student)
    draft = make_exam(teacher, teacher_course)
    response = client.post(
        f"{api}/exams/{draft.id}/join-request", headers=auth_headers(student)
    )
    assert response.status_code == 404


def test_a_finished_exam_refuses_new_requests(
    client, api, auth_headers, teacher, student, teacher_course, make_published_exam, enroll
):
    enroll(teacher_course, student)
    finished = make_published_exam(teacher, teacher_course, starts_in=timedelta(days=-2))

    response = client.post(
        f"{api}/exams/{finished.id}/join-request", headers=auth_headers(student)
    )
    assert response.status_code == 409
    assert response.json()["code"] == "exam_closed"


def test_teachers_cannot_request_to_join(client, api, auth_headers, teacher, enrolled_exam):
    response = client.post(
        f"{api}/exams/{enrolled_exam.id}/join-request", headers=auth_headers(teacher)
    )
    assert response.status_code == 403


def test_the_owning_teacher_sees_the_request(
    client, api, auth_headers, teacher, student, enrolled_exam
):
    client.post(f"{api}/exams/{enrolled_exam.id}/join-request", headers=auth_headers(student))

    body = client.get(
        f"{api}/exams/{enrolled_exam.id}/join-requests", headers=auth_headers(teacher)
    ).json()
    assert len(body) == 1
    assert body[0]["student"]["name"] == student.name
    assert body[0]["status"] == "pending"


def test_another_teacher_sees_nothing(
    client, api, auth_headers, other_teacher, student, enrolled_exam
):
    client.post(f"{api}/exams/{enrolled_exam.id}/join-request", headers=auth_headers(student))
    response = client.get(
        f"{api}/exams/{enrolled_exam.id}/join-requests", headers=auth_headers(other_teacher)
    )
    assert response.status_code == 404


def test_approving_records_who_decided_and_when(
    client, api, auth_headers, teacher, student, enrolled_exam
):
    request_id = client.post(
        f"{api}/exams/{enrolled_exam.id}/join-request", headers=auth_headers(student)
    ).json()["id"]

    response = client.post(
        f"{api}/join-requests/{request_id}/approve", headers=auth_headers(teacher)
    )
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "approved"
    assert body["reviewed_by"] == teacher.id
    assert body["reviewed_at"] is not None

    student_view = client.get(
        f"{api}/exams/{enrolled_exam.id}", headers=auth_headers(student)
    ).json()
    assert student_view["join_request_status"] == "approved"
    assert student_view["can_request_join"] is False


def test_deciding_twice_is_refused(
    client, api, auth_headers, teacher, student, enrolled_exam
):
    request_id = client.post(
        f"{api}/exams/{enrolled_exam.id}/join-request", headers=auth_headers(student)
    ).json()["id"]
    headers = auth_headers(teacher)

    assert client.post(f"{api}/join-requests/{request_id}/approve", headers=headers).status_code == 200
    second = client.post(f"{api}/join-requests/{request_id}/reject", headers=headers)
    assert second.status_code == 409
    assert second.json()["code"] == "already_reviewed"


def test_a_rejected_student_may_ask_again(
    client, api, auth_headers, teacher, student, enrolled_exam
):
    url = f"{api}/exams/{enrolled_exam.id}/join-request"
    student_headers = auth_headers(student)

    first = client.post(url, headers=student_headers).json()["id"]
    client.post(f"{api}/join-requests/{first}/reject", headers=auth_headers(teacher))

    view = client.get(f"{api}/exams/{enrolled_exam.id}", headers=student_headers).json()
    assert view["join_request_status"] == "rejected"
    assert view["can_request_join"] is True, "a rejection is not a permanent ban"

    # The partial unique index only forbids two *pending* requests, so this succeeds.
    again = client.post(url, headers=student_headers)
    assert again.status_code == 201
    assert again.json()["status"] == "pending"


def test_a_student_cannot_decide_their_own_request(
    client, api, auth_headers, student, enrolled_exam
):
    headers = auth_headers(student)
    request_id = client.post(
        f"{api}/exams/{enrolled_exam.id}/join-request", headers=headers
    ).json()["id"]

    assert client.post(f"{api}/join-requests/{request_id}/approve", headers=headers).status_code == 403
    assert client.post(f"{api}/join-requests/{request_id}/reject", headers=headers).status_code == 403


def test_another_teacher_cannot_decide_my_students_request(
    client, api, auth_headers, other_teacher, student, enrolled_exam
):
    request_id = client.post(
        f"{api}/exams/{enrolled_exam.id}/join-request", headers=auth_headers(student)
    ).json()["id"]

    response = client.post(
        f"{api}/join-requests/{request_id}/approve", headers=auth_headers(other_teacher)
    )
    assert response.status_code == 404


def test_approve_all_decides_every_pending_request_at_once(
    client, api, auth_headers, teacher, teacher_course, make_published_exam, make_user, enroll
):
    from app.models.enums import UserRole

    exam = make_published_exam(teacher, teacher_course)
    students = [make_user(UserRole.STUDENT, login_id=f"2026100{n}") for n in range(3)]
    for person in students:
        enroll(teacher_course, person)
        client.post(f"{api}/exams/{exam.id}/join-request", headers=auth_headers(person))

    response = client.post(
        f"{api}/exams/{exam.id}/join-requests/approve-all", headers=auth_headers(teacher)
    )
    assert response.status_code == 200
    assert response.json() == {"updated": 3, "status": "approved"}

    listed = client.get(
        f"{api}/exams/{exam.id}/join-requests", headers=auth_headers(teacher)
    ).json()
    assert {item["status"] for item in listed} == {"approved"}


def test_approve_all_can_be_limited_to_the_requests_the_teacher_saw(
    client, api, auth_headers, teacher, teacher_course, make_published_exam, make_user, enroll
):
    from app.models.enums import UserRole

    exam = make_published_exam(teacher, teacher_course)
    ids = []
    for n in range(3):
        person = make_user(UserRole.STUDENT, login_id=f"2026200{n}")
        enroll(teacher_course, person)
        ids.append(
            client.post(
                f"{api}/exams/{exam.id}/join-request", headers=auth_headers(person)
            ).json()["id"]
        )

    response = client.post(
        f"{api}/exams/{exam.id}/join-requests/approve-all",
        headers=auth_headers(teacher),
        json={"request_ids": ids[:2]},
    )
    assert response.json()["updated"] == 2

    listed = client.get(
        f"{api}/exams/{exam.id}/join-requests", headers=auth_headers(teacher)
    ).json()
    by_id = {item["id"]: item["status"] for item in listed}
    assert by_id[ids[0]] == "approved"
    assert by_id[ids[1]] == "approved"
    assert by_id[ids[2]] == "pending", "a request created after the screen loaded is untouched"


def test_reject_all_is_available_too(
    client, api, auth_headers, teacher, student, enrolled_exam
):
    client.post(f"{api}/exams/{enrolled_exam.id}/join-request", headers=auth_headers(student))
    response = client.post(
        f"{api}/exams/{enrolled_exam.id}/join-requests/reject-all",
        headers=auth_headers(teacher),
    )
    assert response.json() == {"updated": 1, "status": "rejected"}


def test_bulk_review_is_refused_for_another_teachers_exam(
    client, api, auth_headers, other_teacher, enrolled_exam
):
    response = client.post(
        f"{api}/exams/{enrolled_exam.id}/join-requests/approve-all",
        headers=auth_headers(other_teacher),
    )
    assert response.status_code == 404


def test_a_student_can_list_their_own_requests(
    client, api, auth_headers, teacher, student, teacher_course, make_published_exam, enroll
):
    enroll(teacher_course, student)
    first = make_published_exam(teacher, teacher_course, title="Mid Term")
    second = make_published_exam(teacher, teacher_course, title="Final")
    headers = auth_headers(student)
    client.post(f"{api}/exams/{first.id}/join-request", headers=headers)
    client.post(f"{api}/exams/{second.id}/join-request", headers=headers)

    body = client.get(f"{api}/join-requests/mine", headers=headers).json()
    assert {item["exam_title"] for item in body} == {"Mid Term", "Final"}
    assert {item["course_code"] for item in body} == {teacher_course.course_code}
    assert {item["status"] for item in body} == {"pending"}


def test_my_requests_shows_only_my_own(
    client, api, auth_headers, teacher, student, other_student, teacher_course,
    make_published_exam, enroll,
):
    enroll(teacher_course, student)
    enroll(teacher_course, other_student)
    exam = make_published_exam(teacher, teacher_course)
    client.post(f"{api}/exams/{exam.id}/join-request", headers=auth_headers(student))

    assert client.get(f"{api}/join-requests/mine", headers=auth_headers(other_student)).json() == []


def test_teachers_have_no_my_requests_list(client, api, auth_headers, teacher):
    assert client.get(f"{api}/join-requests/mine", headers=auth_headers(teacher)).status_code == 403
