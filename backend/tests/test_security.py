"""Security regression tests.

Each of these encodes a way the system could leak data or accept a forged request. They
are the executable form of docs/security.md §12.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import jwt

from app.core.config import settings


def _forge(claims: dict, key: str | None = None) -> str:
    return jwt.encode(claims, key or settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def _base_claims(subject: int, token_type: str = "access") -> dict:
    now = datetime.now(UTC)
    return {
        "sub": str(subject),
        "type": token_type,
        "jti": uuid.uuid4().hex,
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(minutes=5)).timestamp()),
        "role": "student",
    }


# --------------------------------------------------------------------- token abuse


def test_refresh_token_is_not_accepted_as_a_bearer_credential(client, api, login, student):
    """Without the `type` claim check a 7-day refresh token would work as an API key."""
    tokens = login(student).json()
    response = client.get(
        f"{api}/auth/me", headers={"Authorization": f"Bearer {tokens['refresh_token']}"}
    )
    assert response.status_code == 401


def test_access_token_cannot_be_replayed_at_the_refresh_endpoint(client, api, login, student):
    tokens = login(student).json()
    response = client.post(f"{api}/auth/refresh", json={"refresh_token": tokens["access_token"]})
    assert response.status_code == 401


def test_expired_access_token_is_rejected(client, api, student):
    past = datetime.now(UTC) - timedelta(minutes=1)
    claims = _base_claims(student.id) | {"exp": int(past.timestamp())}
    response = client.get(f"{api}/auth/me", headers={"Authorization": f"Bearer {_forge(claims)}"})
    assert response.status_code == 401
    assert "expired" in response.json()["detail"].lower()


def test_token_signed_with_another_key_is_rejected(client, api, student):
    forged = _forge(_base_claims(student.id), key="an-attacker-controlled-signing-key")
    response = client.get(f"{api}/auth/me", headers={"Authorization": f"Bearer {forged}"})
    assert response.status_code == 401


def test_tampered_token_is_rejected(client, api, auth_headers, student):
    token = auth_headers(student)["Authorization"].removeprefix("Bearer ")
    header, payload, signature = token.split(".")
    tampered = f"{header}.{payload}.{'A' * len(signature)}"
    response = client.get(f"{api}/auth/me", headers={"Authorization": f"Bearer {tampered}"})
    assert response.status_code == 401


def test_forged_role_claim_does_not_grant_admin(client, api, student):
    """The role claim is a hint; authorization re-reads the row, so lying about it fails."""
    forged = _forge(_base_claims(student.id) | {"role": "admin"})
    response = client.get(f"{api}/users", headers={"Authorization": f"Bearer {forged}"})
    assert response.status_code == 403


def test_token_for_a_nonexistent_user_is_rejected(client, api):
    response = client.get(
        f"{api}/auth/me", headers={"Authorization": f"Bearer {_forge(_base_claims(999999))}"}
    )
    assert response.status_code == 401


def test_reusing_a_rotated_refresh_token_revokes_the_whole_family(client, api, login, student):
    first = login(student).json()
    second = client.post(
        f"{api}/auth/refresh", json={"refresh_token": first["refresh_token"]}
    ).json()

    # Replaying the already-rotated token is treated as theft.
    replay = client.post(f"{api}/auth/refresh", json={"refresh_token": first["refresh_token"]})
    assert replay.status_code == 401

    # ...and the legitimate successor is invalidated too, forcing a fresh login.
    after = client.post(f"{api}/auth/refresh", json={"refresh_token": second["refresh_token"]})
    assert after.status_code == 401


def test_deactivating_a_user_invalidates_live_access_tokens(
    client, api, auth_headers, admin, student
):
    student_headers = auth_headers(student)
    assert client.get(f"{api}/auth/me", headers=student_headers).status_code == 200

    client.patch(
        f"{api}/users/{student.id}", headers=auth_headers(admin), json={"is_active": False}
    )

    # No waiting for the token to expire: the user row is re-read on every request.
    assert client.get(f"{api}/auth/me", headers=student_headers).status_code == 401


# ------------------------------------------------------------------ authorization


def test_student_cannot_reach_admin_endpoints(client, api, auth_headers, student):
    headers = auth_headers(student)
    assert client.get(f"{api}/users", headers=headers).status_code == 403
    escalation = client.post(
        f"{api}/users",
        headers=headers,
        json={
            "user_id": "hacker01",
            "password": "Passw0rd!123",
            "name": "Escalation",
            "role": "admin",
        },
    )
    assert escalation.status_code == 403


def test_teacher_cannot_read_another_teachers_course(
    client, api, auth_headers, teacher, other_teacher, make_course
):
    course = make_course(other_teacher)
    response = client.get(f"{api}/courses/{course.id}", headers=auth_headers(teacher))
    # 404, not 403: confirming the course exists would itself be a disclosure.
    assert response.status_code == 404


def test_teacher_cannot_modify_another_teachers_course(
    client, api, auth_headers, teacher, other_teacher, make_course
):
    course = make_course(other_teacher)
    response = client.patch(
        f"{api}/courses/{course.id}",
        headers=auth_headers(teacher),
        json={"course_name": "Hijacked"},
    )
    assert response.status_code == 404


def test_teacher_cannot_enrol_students_into_another_teachers_course(
    client, api, auth_headers, teacher, other_teacher, student, make_course
):
    course = make_course(other_teacher)
    response = client.post(
        f"{api}/courses/{course.id}/enrollments",
        headers=auth_headers(teacher),
        json={"student_user_id": student.user_id},
    )
    assert response.status_code == 404


def test_teacher_cannot_read_another_teachers_enrolment_list(
    client, api, auth_headers, teacher, other_teacher, student, make_course, enroll
):
    course = make_course(other_teacher)
    enroll(course, student)
    response = client.get(
        f"{api}/courses/{course.id}/enrollments", headers=auth_headers(teacher)
    )
    assert response.status_code == 404


def test_enrolled_student_can_read_but_not_modify_the_course(
    client, api, auth_headers, teacher, student, make_course, enroll
):
    course = make_course(teacher)
    enroll(course, student)
    headers = auth_headers(student)

    assert client.get(f"{api}/courses/{course.id}", headers=headers).status_code == 200
    # Visible, so 403 rather than 404 - the object is not hidden, the action is denied.
    denied = client.patch(
        f"{api}/courses/{course.id}", headers=headers, json={"course_name": "Renamed"}
    )
    assert denied.status_code == 403


def test_student_cannot_read_a_course_they_are_not_enrolled_in(
    client, api, auth_headers, teacher, student, make_course
):
    course = make_course(teacher)
    response = client.get(f"{api}/courses/{course.id}", headers=auth_headers(student))
    assert response.status_code == 404


def test_every_protected_endpoint_refuses_anonymous_access(client, api):
    endpoints = [
        ("get", f"{api}/auth/me"),
        ("get", f"{api}/users/me"),
        ("get", f"{api}/users"),
        ("get", f"{api}/departments"),
        ("get", f"{api}/courses"),
        ("post", f"{api}/courses"),
    ]
    for method, path in endpoints:
        response = (
            client.post(path, json={}) if method == "post" else client.get(path)
        )
        assert response.status_code == 401, f"{method.upper()} {path} allowed anonymous access"


# ------------------------------------------------------------------ data exposure


def test_password_hash_is_never_serialised(client, api, auth_headers, admin, student):
    bodies = [
        client.get(f"{api}/auth/me", headers=auth_headers(student)).text,
        client.get(f"{api}/users/me", headers=auth_headers(student)).text,
        client.get(f"{api}/users", headers=auth_headers(admin)).text,
        client.get(f"{api}/users/{student.id}", headers=auth_headers(admin)).text,
    ]
    for body in bodies:
        assert "password_hash" not in body
        assert "$argon2" not in body
