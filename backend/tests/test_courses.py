from __future__ import annotations

from app.models.enums import UserRole


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


# --------------------------------------------------------------- bulk enrolment


def test_bulk_enrolment_admits_a_whole_roll_list(
    client, api, auth_headers, teacher, make_user, make_course
):
    course = make_course(teacher)
    students = [make_user(UserRole.STUDENT) for _ in range(3)]

    response = client.post(
        f"{api}/courses/{course.id}/enrollments/bulk",
        headers=auth_headers(teacher),
        json={"student_user_ids": [s.user_id for s in students]},
    )
    assert response.status_code == 200
    body = response.json()
    assert [item["user_id"] for item in body["enrolled"]] == [s.user_id for s in students]
    assert body["skipped"] == []

    listing = client.get(f"{api}/courses/{course.id}/enrollments", headers=auth_headers(teacher))
    assert len(listing.json()) == 3


def test_one_bad_id_does_not_cost_the_rest_their_places(
    client, api, auth_headers, teacher, student, make_course
):
    """The whole point of the batch: a typo is reported, not fatal."""
    course = make_course(teacher)
    response = client.post(
        f"{api}/courses/{course.id}/enrollments/bulk",
        headers=auth_headers(teacher),
        json={"student_user_ids": ["nosuchstudent", student.user_id]},
    )
    assert response.status_code == 200
    body = response.json()
    assert [item["user_id"] for item in body["enrolled"]] == [student.user_id]
    assert body["skipped"] == [
        {"student_user_id": "nosuchstudent", "reason": "not_found"}
    ]


def test_each_kind_of_skip_is_named(
    client, api, auth_headers, teacher, other_teacher, student, make_user, make_course, enroll
):
    """A teacher fixing a list needs to know which id failed and why, not just a count."""
    course = make_course(teacher)
    seated = make_user(UserRole.STUDENT)
    enroll(course, seated)
    deactivated = make_user(UserRole.STUDENT, is_active=False)

    response = client.post(
        f"{api}/courses/{course.id}/enrollments/bulk",
        headers=auth_headers(teacher),
        json={
            "student_user_ids": [
                "ghost",
                other_teacher.user_id,
                deactivated.user_id,
                seated.user_id,
                student.user_id,
            ]
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert [item["user_id"] for item in body["enrolled"]] == [student.user_id]
    assert body["skipped"] == [
        {"student_user_id": "ghost", "reason": "not_found"},
        {"student_user_id": other_teacher.user_id, "reason": "not_a_student"},
        {"student_user_id": deactivated.user_id, "reason": "deactivated"},
        {"student_user_id": seated.user_id, "reason": "already_enrolled"},
    ]


def test_a_repeated_id_enrols_once(
    client, api, auth_headers, teacher, student, make_course
):
    course = make_course(teacher)
    response = client.post(
        f"{api}/courses/{course.id}/enrollments/bulk",
        headers=auth_headers(teacher),
        json={"student_user_ids": [student.user_id, student.user_id]},
    )
    assert response.status_code == 200
    body = response.json()
    assert len(body["enrolled"]) == 1
    # Collapsed on the way in, so the repeat is not reported as "already enrolled".
    assert body["skipped"] == []

    listing = client.get(f"{api}/courses/{course.id}/enrollments", headers=auth_headers(teacher))
    assert len(listing.json()) == 1


def test_bulk_enrolment_respects_course_ownership(
    client, api, auth_headers, other_teacher, student, teacher, make_course
):
    course = make_course(teacher)
    response = client.post(
        f"{api}/courses/{course.id}/enrollments/bulk",
        headers=auth_headers(other_teacher),
        json={"student_user_ids": [student.user_id]},
    )
    # 404, not 403: whether course 42 exists is itself none of their business.
    assert response.status_code == 404


def test_a_student_cannot_enrol_anyone(
    client, api, auth_headers, student, other_student, teacher, make_course
):
    course = make_course(teacher)
    response = client.post(
        f"{api}/courses/{course.id}/enrollments/bulk",
        headers=auth_headers(student),
        json={"student_user_ids": [other_student.user_id]},
    )
    assert response.status_code == 403


def test_an_oversized_batch_is_refused(
    client, api, auth_headers, teacher, make_course
):
    course = make_course(teacher)
    response = client.post(
        f"{api}/courses/{course.id}/enrollments/bulk",
        headers=auth_headers(teacher),
        json={"student_user_ids": [f"s{n}" for n in range(201)]},
    )
    assert response.status_code == 422


# ------------------------------------------------- putting a teacher in charge


def _assign(client, api, auth_headers, actor, course_id, login_id):
    return client.post(
        f"{api}/courses/{course_id}/assign",
        headers=auth_headers(actor),
        json={"teacher_user_id": login_id},
    )


def test_an_admin_hands_a_course_to_a_teacher(
    client, api, auth_headers, admin, teacher, other_teacher, make_course
):
    course = make_course(teacher)
    response = _assign(client, api, auth_headers, admin, course.id, other_teacher.user_id)

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["course"]["created_by"] == other_teacher.id
    assert body["course"]["teacher_name"] == other_teacher.name


def test_the_new_teacher_can_now_manage_it_and_the_old_one_cannot(
    client, api, auth_headers, admin, teacher, other_teacher, make_course
):
    """Ownership is what decides who may edit a course, so this is the whole point."""
    course = make_course(teacher)
    _assign(client, api, auth_headers, admin, course.id, other_teacher.user_id)

    assert client.patch(
        f"{api}/courses/{course.id}",
        headers=auth_headers(other_teacher),
        json={"course_name": "Renamed by the new holder"},
    ).status_code == 200
    # And it is no longer the previous teacher's to change -- not found, because it is
    # no longer visible to them at all.
    assert client.patch(
        f"{api}/courses/{course.id}",
        headers=auth_headers(teacher),
        json={"course_name": "Renamed by the old holder"},
    ).status_code == 404


def test_exams_keep_their_author_and_the_count_says_so(
    client, api, auth_headers, admin, teacher, other_teacher, teacher_course,
    make_published_exam,
):
    """An exam is somebody's work and its results point at them.

    Rewriting that because the course changed hands would misattribute it, so the
    response reports what stayed rather than leaving the new teacher to discover it.
    """
    make_published_exam(teacher, teacher_course)
    make_published_exam(teacher, teacher_course)

    response = _assign(
        client, api, auth_headers, admin, teacher_course.id, other_teacher.user_id
    )
    assert response.status_code == 200
    assert response.json()["exams_kept_by_previous_teacher"] == 2


def test_a_student_cannot_be_put_in_charge(
    client, api, auth_headers, admin, teacher, student, make_course
):
    course = make_course(teacher)
    response = _assign(client, api, auth_headers, admin, course.id, student.user_id)
    assert response.status_code == 400
    assert response.json()["code"] == "not_a_teacher"


def test_a_deactivated_teacher_cannot_be_put_in_charge(
    client, api, auth_headers, admin, teacher, other_teacher, make_course, db
):
    other_teacher.is_active = False
    db.commit()

    course = make_course(teacher)
    response = _assign(client, api, auth_headers, admin, course.id, other_teacher.user_id)
    assert response.status_code == 400
    assert response.json()["code"] == "user_deactivated"


def test_assigning_to_the_current_holder_is_refused(
    client, api, auth_headers, admin, teacher, make_course
):
    course = make_course(teacher)
    response = _assign(client, api, auth_headers, admin, course.id, teacher.user_id)
    assert response.status_code == 409
    assert response.json()["code"] == "already_assigned"


def test_an_unknown_login_is_not_found(
    client, api, auth_headers, admin, teacher, make_course
):
    course = make_course(teacher)
    assert _assign(
        client, api, auth_headers, admin, course.id, "nobody"
    ).status_code == 404


def test_only_an_admin_may_assign(
    client, api, auth_headers, teacher, other_teacher, student, make_course
):
    course = make_course(teacher)
    # Not even the teacher who currently holds it: handing work to someone else is an
    # administrative act, not an editorial one.
    assert _assign(
        client, api, auth_headers, teacher, course.id, other_teacher.user_id
    ).status_code == 403
    assert _assign(
        client, api, auth_headers, student, course.id, other_teacher.user_id
    ).status_code == 403


def test_the_course_list_names_who_runs_each_one(
    client, api, auth_headers, admin, teacher, make_course
):
    make_course(teacher)
    page = client.get(f"{api}/courses", headers=auth_headers(admin)).json()
    assert page["items"][0]["teacher_name"] == teacher.name
