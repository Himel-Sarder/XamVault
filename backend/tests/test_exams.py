from __future__ import annotations

from tests.conftest import mcq_payload


def test_teacher_creates_a_draft_exam_in_their_own_course(
    client, api, auth_headers, teacher, teacher_course, future_start
):
    response = client.post(
        f"{api}/exams",
        headers=auth_headers(teacher),
        json={
            "course_id": teacher_course.id,
            "title": "Mid Term Quiz",
            "description": "Covers chapters 1-4",
            "start_at": future_start,
            "duration_minutes": 30,
        },
    )
    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "draft"
    assert body["teacher_id"] == teacher.id
    assert body["total_marks"] == 0
    assert body["question_count"] == 0
    # expires_at is derived at publish time, not now.
    assert body["expires_at"] is None
    # Settings always exist, so no screen has to cope with them being missing.
    assert body["settings"]["max_attempts"] == 1
    assert body["settings"]["secure_mode"] is True


def test_settings_can_be_chosen_at_creation(
    client, api, auth_headers, teacher, teacher_course, future_start
):
    response = client.post(
        f"{api}/exams",
        headers=auth_headers(teacher),
        json={
            "course_id": teacher_course.id,
            "title": "Shuffled Quiz",
            "start_at": future_start,
            "duration_minutes": 45,
            "settings": {"shuffle_questions": True, "max_attempts": 2},
        },
    )
    assert response.status_code == 201
    settings = response.json()["settings"]
    assert settings["shuffle_questions"] is True
    assert settings["max_attempts"] == 2
    assert settings["shuffle_answers"] is False  # untouched defaults survive


def test_server_owned_fields_cannot_be_forged(
    client, api, auth_headers, teacher, other_teacher, teacher_course, future_start
):
    response = client.post(
        f"{api}/exams",
        headers=auth_headers(teacher),
        json={
            "course_id": teacher_course.id,
            "title": "Forged",
            "start_at": future_start,
            "duration_minutes": 30,
            "teacher_id": other_teacher.id,
            "status": "published",
            "total_marks": 500,
            "expires_at": future_start,
        },
    )
    assert response.status_code == 201
    body = response.json()
    assert body["teacher_id"] == teacher.id
    assert body["status"] == "draft"
    assert body["total_marks"] == 0
    assert body["expires_at"] is None


def test_a_teacher_cannot_create_an_exam_in_someone_elses_course(
    client, api, auth_headers, teacher, other_teacher, make_course, future_start
):
    foreign_course = make_course(other_teacher)
    response = client.post(
        f"{api}/exams",
        headers=auth_headers(teacher),
        json={
            "course_id": foreign_course.id,
            "title": "Not mine",
            "start_at": future_start,
            "duration_minutes": 30,
        },
    )
    assert response.status_code == 404


def test_students_cannot_create_exams(
    client, api, auth_headers, student, teacher_course, future_start
):
    response = client.post(
        f"{api}/exams",
        headers=auth_headers(student),
        json={
            "course_id": teacher_course.id,
            "title": "Nope",
            "start_at": future_start,
            "duration_minutes": 30,
        },
    )
    assert response.status_code == 403


def test_invalid_duration_is_rejected(
    client, api, auth_headers, teacher, teacher_course, future_start
):
    for duration in (0, -5, 60 * 25):
        response = client.post(
            f"{api}/exams",
            headers=auth_headers(teacher),
            json={
                "course_id": teacher_course.id,
                "title": "Bad duration",
                "start_at": future_start,
                "duration_minutes": duration,
            },
        )
        assert response.status_code == 422, duration


def test_exam_list_is_scoped_to_the_calling_teacher(
    client, api, auth_headers, teacher, other_teacher, make_course, make_exam
):
    mine = make_exam(teacher, make_course(teacher, code="CSE-301"))
    make_exam(other_teacher, make_course(other_teacher, code="CSE-302"))

    body = client.get(f"{api}/exams", headers=auth_headers(teacher)).json()
    assert body["total"] == 1
    assert body["items"][0]["id"] == mine.id


def test_filtering_by_another_teachers_course_is_refused(
    client, api, auth_headers, teacher, other_teacher, make_course
):
    # Otherwise the filter would be an oracle for which course ids exist.
    foreign_course = make_course(other_teacher)
    response = client.get(
        f"{api}/exams", headers=auth_headers(teacher), params={"course_id": foreign_course.id}
    )
    assert response.status_code == 404


def test_reading_another_teachers_exam_is_not_found(
    client, api, auth_headers, teacher, other_teacher, make_course, make_exam
):
    foreign = make_exam(other_teacher, make_course(other_teacher))
    assert client.get(f"{api}/exams/{foreign.id}", headers=auth_headers(teacher)).status_code == 404


def test_a_draft_exam_can_be_edited(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    exam = make_exam(teacher, teacher_course)
    response = client.patch(
        f"{api}/exams/{exam.id}",
        headers=auth_headers(teacher),
        json={"title": "Renamed", "duration_minutes": 60},
    )
    assert response.status_code == 200
    assert response.json()["title"] == "Renamed"
    assert response.json()["duration_minutes"] == 60


def test_settings_can_be_updated_on_a_draft(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    exam = make_exam(teacher, teacher_course)
    response = client.put(
        f"{api}/exams/{exam.id}/settings",
        headers=auth_headers(teacher),
        json={"shuffle_questions": True, "shuffle_answers": True, "secure_mode": False},
    )
    assert response.status_code == 200
    settings = response.json()["settings"]
    assert settings["shuffle_questions"] is True
    assert settings["secure_mode"] is False


def test_a_draft_exam_can_be_deleted(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    exam = make_exam(teacher, teacher_course)
    client.post(
        f"{api}/exams/{exam.id}/questions", headers=auth_headers(teacher), json=mcq_payload()
    )
    assert client.delete(f"{api}/exams/{exam.id}", headers=auth_headers(teacher)).status_code == 204
    assert client.get(f"{api}/exams/{exam.id}", headers=auth_headers(teacher)).status_code == 404


def test_another_teacher_cannot_delete_my_exam(
    client, api, auth_headers, teacher, other_teacher, teacher_course, make_exam
):
    exam = make_exam(teacher, teacher_course)
    assert client.delete(
        f"{api}/exams/{exam.id}", headers=auth_headers(other_teacher)
    ).status_code == 404
    assert client.get(f"{api}/exams/{exam.id}", headers=auth_headers(teacher)).status_code == 200


def test_an_admin_sees_every_exam_not_just_their_own(
    client, api, auth_headers, admin, teacher, other_teacher, make_course, make_exam
):
    # An admin may already open any single exam, so a list that showed none would be
    # inconsistent with that.
    make_exam(teacher, make_course(teacher, code="CSE-301"))
    make_exam(other_teacher, make_course(other_teacher, code="CSE-302"))

    body = client.get(f"{api}/exams", headers=auth_headers(admin)).json()
    assert body["total"] == 2
