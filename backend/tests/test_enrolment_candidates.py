"""Finding the students who should be on a course's roll.

Enrolling a cohort by typing ids one at a time is the kind of work software exists to
remove. A teacher picks the year and the half, sees who is there, and adds them.
"""

from __future__ import annotations

import pytest


@pytest.fixture
def cohort(make_user, db):
    """Twelve students spread across two years and both halves.

    make_user files everyone in year 3, half 2; the stage is set here so the filter has
    something to distinguish.
    """
    from app.models.enums import UserRole
    from app.models.user import StudentProfile

    made = []
    for index, (year, semester) in enumerate(
        [(4, 1)] * 5 + [(4, 2)] * 3 + [(3, 1)] * 4, start=1
    ):
        student = make_user(
            UserRole.STUDENT,
            login_id=f"2026{1000 + index}",
            name=f"Student {index:02d}",
        )
        profile = db.query(StudentProfile).filter_by(user_id=student.id).one()
        profile.study_year = year
        profile.semester = semester
        made.append(student)
    db.commit()
    return made


def _candidates(client, api, auth_headers, teacher, course, **params):
    return client.get(
        f"{api}/courses/{course.id}/candidates",
        headers=auth_headers(teacher),
        params=params,
    )


def test_a_year_and_a_half_of_it_narrows_to_that_cohort(
    client, api, auth_headers, teacher, teacher_course, cohort
):
    response = _candidates(
        client, api, auth_headers, teacher, teacher_course, study_year=4, semester=1
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert len(body["items"]) == 5
    assert all(c["study_year"] == 4 and c["semester"] == 1 for c in body["items"])
    assert body["truncated"] is False


def test_the_year_alone_returns_both_halves(
    client, api, auth_headers, teacher, teacher_course, cohort
):
    body = _candidates(
        client, api, auth_headers, teacher, teacher_course, study_year=4
    ).json()

    assert len(body["items"]) == 8


def test_students_already_on_the_roll_are_left_out(
    client, api, auth_headers, teacher, teacher_course, cohort, enroll
):
    """The answer to "add them" is that they are already here."""
    enroll(teacher_course, cohort[0])

    body = _candidates(
        client, api, auth_headers, teacher, teacher_course, study_year=4, semester=1
    ).json()

    assert len(body["items"]) == 4
    assert cohort[0].id not in [c["id"] for c in body["items"]]


def test_it_can_be_searched_by_name_or_student_id(
    client, api, auth_headers, teacher, teacher_course, cohort
):
    by_name = _candidates(
        client, api, auth_headers, teacher, teacher_course, search="Student 03"
    ).json()
    assert [c["name"] for c in by_name["items"]] == ["Student 03"]

    by_id = _candidates(
        client, api, auth_headers, teacher, teacher_course, search="20261007"
    ).json()
    assert [c["student_id"] for c in by_id["items"]] == ["20261007"]


def test_a_deactivated_student_is_not_offered(
    client, api, auth_headers, admin, teacher, teacher_course, cohort
):
    client.patch(
        f"{api}/users/{cohort[0].id}", headers=auth_headers(admin), json={"is_active": False}
    )

    body = _candidates(
        client, api, auth_headers, teacher, teacher_course, study_year=4, semester=1
    ).json()

    assert cohort[0].id not in [c["id"] for c in body["items"]]


def test_another_teacher_cannot_read_my_roll_candidates(
    client, api, auth_headers, other_teacher, teacher_course, cohort
):
    """404, not 403: whether the course exists is not their business."""
    response = _candidates(client, api, auth_headers, other_teacher, teacher_course)
    assert response.status_code == 404


def test_a_student_cannot_read_the_directory_this_way(
    client, api, auth_headers, student, teacher_course
):
    response = _candidates(client, api, auth_headers, student, teacher_course)
    assert response.status_code == 403


def test_a_fifth_year_is_refused_rather_than_returning_nothing(
    client, api, auth_headers, teacher, teacher_course
):
    """A filter outside the programme is a mistake, not an empty cohort."""
    response = _candidates(client, api, auth_headers, teacher, teacher_course, study_year=5)
    assert response.status_code == 422


def test_the_whole_cohort_can_then_be_enrolled_at_once(
    client, api, auth_headers, teacher, teacher_course, cohort
):
    """The point of the screen: pick the year, add everyone in it."""
    body = _candidates(
        client, api, auth_headers, teacher, teacher_course, study_year=4, semester=1
    ).json()

    response = client.post(
        f"{api}/courses/{teacher_course.id}/enrollments/bulk",
        headers=auth_headers(teacher),
        json={"student_user_ids": [c["user_id"] for c in body["items"]]},
    )

    assert response.status_code == 200, response.text
    assert len(response.json()["enrolled"]) == 5
    assert response.json()["skipped"] == []

    after = _candidates(
        client, api, auth_headers, teacher, teacher_course, study_year=4, semester=1
    ).json()
    assert after["items"] == []
