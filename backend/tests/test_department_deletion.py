"""Removing a department.

Nothing goes with it. Every foreign key pointing at a department is SET NULL, and a
department was always optional on both a course and a person, so what is left behind is
unassigned rather than broken.
"""

from __future__ import annotations

import pytest

from app.models.course import Course
from app.models.department import Department
from app.models.user import User


@pytest.fixture
def spare(client, api, auth_headers, admin):
    """A second department, so the fixtures' own one is never the thing under test."""
    created = client.post(
        f"{api}/departments",
        headers=auth_headers(admin),
        json={"code": "FISH", "name": "Fisheries"},
    )
    assert created.status_code == 201, created.text
    return created.json()["id"]


def test_an_empty_department_is_deleted(client, api, auth_headers, admin, spare, db):
    assert client.delete(
        f"{api}/departments/{spare}", headers=auth_headers(admin)
    ).status_code == 204

    db.expunge_all()
    assert db.get(Department, spare) is None


def test_it_is_gone_from_the_list(client, api, auth_headers, admin, spare):
    client.delete(f"{api}/departments/{spare}", headers=auth_headers(admin))

    listed = client.get(f"{api}/departments", headers=auth_headers(admin)).json()
    assert spare not in [d["id"] for d in listed]


def test_the_impact_counts_what_would_be_unassigned(
    client, api, auth_headers, admin, department, teacher, student, teacher_course
):
    impact = client.get(
        f"{api}/departments/{department.id}/deletion-impact",
        headers=auth_headers(admin),
    )

    assert impact.status_code == 200, impact.text
    body = impact.json()
    assert body["courses"] == 1
    assert body["teachers"] >= 1
    assert body["students"] >= 1


def test_courses_survive_without_a_department(
    client, api, auth_headers, admin, department, teacher_course, db
):
    """The course is not deleted; it loses its department and carries on."""
    course_id = teacher_course.id

    assert client.delete(
        f"{api}/departments/{department.id}", headers=auth_headers(admin)
    ).status_code == 204

    db.expunge_all()
    course = db.get(Course, course_id)
    assert course is not None, "deleting a department must not delete its courses"
    assert course.department_id is None


def test_people_survive_without_a_department(
    client, api, auth_headers, admin, department, student, db
):
    student_id = student.id

    client.delete(f"{api}/departments/{department.id}", headers=auth_headers(admin))

    db.expunge_all()
    person = db.get(User, student_id)
    assert person is not None, "deleting a department must not delete its people"
    assert person.department_id is None


def test_a_teacher_cannot_delete_one(client, api, auth_headers, teacher, spare):
    assert client.delete(
        f"{api}/departments/{spare}", headers=auth_headers(teacher)
    ).status_code == 403


def test_a_student_cannot_delete_one(client, api, auth_headers, student, spare):
    assert client.delete(
        f"{api}/departments/{spare}", headers=auth_headers(student)
    ).status_code == 403


def test_deleting_one_that_is_not_there(client, api, auth_headers, admin):
    assert client.delete(
        f"{api}/departments/99999", headers=auth_headers(admin)
    ).status_code == 404


def test_the_impact_of_a_department_that_is_not_there(client, api, auth_headers, admin):
    assert client.get(
        f"{api}/departments/99999/deletion-impact", headers=auth_headers(admin)
    ).status_code == 404
