from __future__ import annotations

from app.models.enums import UserRole


def test_admin_can_create_a_student_with_profile(client, api, auth_headers, admin, department):
    response = client.post(
        f"{api}/users",
        headers=auth_headers(admin),
        json={
            "user_id": "20260001",
            "password": "InitialPassw0rd!",
            "name": "New Student",
            "email": "new.student@example.edu",
            "role": "student",
            "department_id": department.id,
            "student_id": "20260001",
            "semester": 1,
            "session": "2025-2026",
        },
    )
    assert response.status_code == 201
    body = response.json()
    assert body["role"] == "student"
    assert body["student_profile"]["semester"] == 1
    assert "password" not in body and "password_hash" not in body

    # the created account can actually log in
    login = client.post(
        f"{api}/auth/login", json={"user_id": "20260001", "password": "InitialPassw0rd!"}
    )
    assert login.status_code == 200


def test_admin_can_create_a_teacher(client, api, auth_headers, admin, department):
    response = client.post(
        f"{api}/users",
        headers=auth_headers(admin),
        json={
            "user_id": "T3003",
            "password": "InitialPassw0rd!",
            "name": "New Teacher",
            "role": "teacher",
            "department_id": department.id,
            "teacher_id": "T3003",
            "designation": "Professor",
        },
    )
    assert response.status_code == 201
    assert response.json()["teacher_profile"]["designation"] == "Professor"


def test_creating_a_student_without_student_id_is_rejected(client, api, auth_headers, admin):
    response = client.post(
        f"{api}/users",
        headers=auth_headers(admin),
        json={
            "user_id": "20260002",
            "password": "InitialPassw0rd!",
            "name": "No Profile",
            "role": "student",
        },
    )
    assert response.status_code == 422


def test_duplicate_user_id_conflicts(client, api, auth_headers, admin, student):
    response = client.post(
        f"{api}/users",
        headers=auth_headers(admin),
        json={
            "user_id": student.user_id,
            "password": "InitialPassw0rd!",
            "name": "Clash",
            "role": "student",
            "student_id": "99999999",
        },
    )
    assert response.status_code == 409


def test_unknown_department_is_rejected(client, api, auth_headers, admin):
    response = client.post(
        f"{api}/users",
        headers=auth_headers(admin),
        json={
            "user_id": "20260003",
            "password": "InitialPassw0rd!",
            "name": "Ghost Dept",
            "role": "student",
            "student_id": "20260003",
            "department_id": 9999,
        },
    )
    assert response.status_code == 400


def test_admin_can_list_and_filter_users(client, api, auth_headers, admin, teacher, student):
    response = client.get(f"{api}/users", headers=auth_headers(admin), params={"role": "student"})
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["user_id"] == student.user_id


def test_admin_can_deactivate_a_user(client, api, auth_headers, admin, student, login):
    response = client.patch(
        f"{api}/users/{student.id}", headers=auth_headers(admin), json={"is_active": False}
    )
    assert response.status_code == 200
    assert response.json()["is_active"] is False
    assert login(student).status_code == 401


def test_users_me_works_for_every_role(client, api, auth_headers, make_user):
    for role in (UserRole.ADMIN, UserRole.TEACHER, UserRole.STUDENT):
        user = make_user(role)
        response = client.get(f"{api}/users/me", headers=auth_headers(user))
        assert response.status_code == 200
        assert response.json()["role"] == role.value


def test_departments_are_readable_by_any_role_but_created_by_admin_only(
    client, api, auth_headers, admin, teacher, department
):
    assert client.get(f"{api}/departments", headers=auth_headers(teacher)).status_code == 200

    denied = client.post(
        f"{api}/departments", headers=auth_headers(teacher), json={"code": "eee", "name": "EEE"}
    )
    assert denied.status_code == 403

    created = client.post(
        f"{api}/departments", headers=auth_headers(admin), json={"code": "eee", "name": "EEE"}
    )
    assert created.status_code == 201
    assert created.json()["code"] == "EEE"  # normalised to upper case
