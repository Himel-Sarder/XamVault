from __future__ import annotations


def test_teacher_creates_a_course_and_owns_it(client, api, auth_headers, teacher, department):
    response = client.post(
        f"{api}/courses",
        headers=auth_headers(teacher),
        json={
            "course_code": "cse-301",
            "course_name": "Database Management System",
            "department_id": department.id,
            "semester": 6,
            "session": "2025-2026",
        },
    )
    assert response.status_code == 201
    body = response.json()
    assert body["course_code"] == "CSE-301"  # normalised
    assert body["created_by"] == teacher.id


def test_created_by_cannot_be_forged_by_the_client(
    client, api, auth_headers, teacher, other_teacher
):
    """`created_by` is taken from the token; a body field of that name is simply ignored."""
    response = client.post(
        f"{api}/courses",
        headers=auth_headers(teacher),
        json={
            "course_code": "CSE-401",
            "course_name": "Compiler Design",
            "created_by": other_teacher.id,
            "teacher_id": other_teacher.id,
        },
    )
    assert response.status_code == 201
    assert response.json()["created_by"] == teacher.id


def test_students_cannot_create_courses(client, api, auth_headers, student):
    response = client.post(
        f"{api}/courses",
        headers=auth_headers(student),
        json={"course_code": "CSE-501", "course_name": "Not Allowed"},
    )
    assert response.status_code == 403


def test_duplicate_code_in_the_same_session_conflicts(client, api, auth_headers, teacher):
    payload = {"course_code": "CSE-301", "course_name": "DBMS", "session": "2025-2026"}
    assert client.post(f"{api}/courses", headers=auth_headers(teacher), json=payload).status_code == 201
    again = client.post(f"{api}/courses", headers=auth_headers(teacher), json=payload)
    assert again.status_code == 409


def test_same_code_in_a_different_session_is_allowed(client, api, auth_headers, teacher):
    first = {"course_code": "CSE-301", "course_name": "DBMS", "session": "2024-2025"}
    second = {"course_code": "CSE-301", "course_name": "DBMS", "session": "2025-2026"}
    assert client.post(f"{api}/courses", headers=auth_headers(teacher), json=first).status_code == 201
    assert client.post(f"{api}/courses", headers=auth_headers(teacher), json=second).status_code == 201


def test_teacher_list_is_scoped_to_own_courses(
    client, api, auth_headers, teacher, other_teacher, make_course
):
    mine = make_course(teacher, code="CSE-301")
    make_course(other_teacher, code="CSE-302")

    response = client.get(f"{api}/courses", headers=auth_headers(teacher))
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["id"] == mine.id


def test_student_list_is_scoped_to_enrolled_courses(
    client, api, auth_headers, teacher, student, make_course, enroll
):
    enrolled = make_course(teacher, code="CSE-301")
    make_course(teacher, code="CSE-302")
    enroll(enrolled, student)

    body = client.get(f"{api}/courses", headers=auth_headers(student)).json()
    assert body["total"] == 1
    assert body["items"][0]["id"] == enrolled.id


def test_admin_sees_every_course(
    client, api, auth_headers, admin, teacher, other_teacher, make_course
):
    make_course(teacher, code="CSE-301")
    make_course(other_teacher, code="CSE-302")
    assert client.get(f"{api}/courses", headers=auth_headers(admin)).json()["total"] == 2


def test_pagination_reports_totals(client, api, auth_headers, teacher, make_course):
    for index in range(5):
        make_course(teacher, code=f"CSE-{400 + index}")
    body = client.get(
        f"{api}/courses", headers=auth_headers(teacher), params={"page": 2, "page_size": 2}
    ).json()
    assert body["total"] == 5
    assert body["page"] == 2
    assert len(body["items"]) == 2


def test_teacher_can_update_own_course(client, api, auth_headers, teacher, make_course):
    course = make_course(teacher)
    response = client.patch(
        f"{api}/courses/{course.id}",
        headers=auth_headers(teacher),
        json={"course_name": "Advanced DBMS", "is_active": False},
    )
    assert response.status_code == 200
    assert response.json()["course_name"] == "Advanced DBMS"
    assert response.json()["is_active"] is False


def test_enrolling_a_student(client, api, auth_headers, teacher, student, make_course):
    course = make_course(teacher)
    response = client.post(
        f"{api}/courses/{course.id}/enrollments",
        headers=auth_headers(teacher),
        json={"student_user_id": student.user_id},
    )
    assert response.status_code == 201
    assert response.json()["student"]["user_id"] == student.user_id

    listing = client.get(f"{api}/courses/{course.id}/enrollments", headers=auth_headers(teacher))
    assert [item["student_id"] for item in listing.json()] == [student.id]


def test_duplicate_enrollment_conflicts(client, api, auth_headers, teacher, student, make_course):
    course = make_course(teacher)
    payload = {"student_user_id": student.user_id}
    url = f"{api}/courses/{course.id}/enrollments"
    assert client.post(url, headers=auth_headers(teacher), json=payload).status_code == 201
    assert client.post(url, headers=auth_headers(teacher), json=payload).status_code == 409


def test_a_teacher_cannot_be_enrolled_as_a_student(
    client, api, auth_headers, teacher, other_teacher, make_course
):
    course = make_course(teacher)
    response = client.post(
        f"{api}/courses/{course.id}/enrollments",
        headers=auth_headers(teacher),
        json={"student_user_id": other_teacher.user_id},
    )
    assert response.status_code == 400


def test_unenrolling_removes_access(
    client, api, auth_headers, teacher, student, make_course, enroll
):
    course = make_course(teacher)
    enroll(course, student)
    assert client.get(f"{api}/courses", headers=auth_headers(student)).json()["total"] == 1

    response = client.delete(
        f"{api}/courses/{course.id}/enrollments/{student.id}", headers=auth_headers(teacher)
    )
    assert response.status_code == 204
    assert client.get(f"{api}/courses", headers=auth_headers(student)).json()["total"] == 0
