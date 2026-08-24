from __future__ import annotations

from app.models.enums import UserRole


def test_login_returns_tokens_and_user(client, api, student):
    response = client.post(
        f"{api}/auth/login", json={"user_id": student.user_id, "password": "TestPassw0rd!"}
    )
    assert response.status_code == 200
    body = response.json()
    assert body["token_type"] == "bearer"
    assert body["access_token"] and body["refresh_token"]
    assert body["expires_in"] == 30 * 60
    assert body["user"] == {
        "id": student.id,
        "user_id": student.user_id,
        "name": student.name,
        "role": "student",
    }


def test_login_with_wrong_password_is_rejected(client, api, student):
    response = client.post(
        f"{api}/auth/login", json={"user_id": student.user_id, "password": "wrong-password"}
    )
    assert response.status_code == 401


def test_unknown_user_and_wrong_password_are_indistinguishable(client, api, student):
    """A different message for "no such user" would turn login into a user-id directory."""
    wrong_password = client.post(
        f"{api}/auth/login", json={"user_id": student.user_id, "password": "wrong-password"}
    )
    unknown_user = client.post(
        f"{api}/auth/login", json={"user_id": "does-not-exist", "password": "wrong-password"}
    )
    assert wrong_password.status_code == unknown_user.status_code == 401
    assert wrong_password.json()["detail"] == unknown_user.json()["detail"]


def test_deactivated_account_cannot_log_in(client, api, make_user):
    inactive = make_user(UserRole.STUDENT, login_id="20269999", is_active=False)
    response = client.post(
        f"{api}/auth/login", json={"user_id": inactive.user_id, "password": "TestPassw0rd!"}
    )
    assert response.status_code == 401
    assert "deactivated" in response.json()["detail"].lower()


def test_me_returns_the_authenticated_user_with_profile(client, api, auth_headers, student):
    response = client.get(f"{api}/auth/me", headers=auth_headers(student))
    assert response.status_code == 200
    body = response.json()
    assert body["user_id"] == student.user_id
    assert body["role"] == "student"
    assert body["student_profile"]["student_id"] == student.user_id
    assert body["teacher_profile"] is None


def test_me_requires_a_token(client, api):
    response = client.get(f"{api}/auth/me")
    assert response.status_code == 401
    assert response.headers.get("WWW-Authenticate") == "Bearer"


def test_refresh_rotates_and_returns_a_new_pair(client, api, login, student):
    first = login(student).json()
    response = client.post(f"{api}/auth/refresh", json={"refresh_token": first["refresh_token"]})
    assert response.status_code == 200
    second = response.json()
    assert second["refresh_token"] != first["refresh_token"]
    # the new access token works
    assert (
        client.get(
            f"{api}/auth/me", headers={"Authorization": f"Bearer {second['access_token']}"}
        ).status_code
        == 200
    )


def test_logout_revokes_the_refresh_token(client, api, login, student):
    tokens = login(student).json()
    assert client.post(
        f"{api}/auth/logout", json={"refresh_token": tokens["refresh_token"]}
    ).status_code == 204
    replay = client.post(f"{api}/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert replay.status_code == 401


def test_change_password_updates_credentials_and_kills_sessions(client, api, login, student):
    tokens = login(student).json()
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}

    response = client.post(
        f"{api}/auth/change-password",
        json={"current_password": "TestPassw0rd!", "new_password": "BrandNewPassw0rd!"},
        headers=headers,
    )
    assert response.status_code == 204

    assert login(student, "TestPassw0rd!").status_code == 401
    assert login(student, "BrandNewPassw0rd!").status_code == 200
    # the refresh token issued before the change no longer works
    assert (
        client.post(
            f"{api}/auth/refresh", json={"refresh_token": tokens["refresh_token"]}
        ).status_code
        == 401
    )


def test_change_password_requires_the_current_one(client, api, auth_headers, student):
    response = client.post(
        f"{api}/auth/change-password",
        json={"current_password": "not-the-password", "new_password": "BrandNewPassw0rd!"},
        headers=auth_headers(student),
    )
    assert response.status_code == 401


def test_short_new_password_is_rejected(client, api, auth_headers, student):
    response = client.post(
        f"{api}/auth/change-password",
        json={"current_password": "TestPassw0rd!", "new_password": "short"},
        headers=auth_headers(student),
    )
    assert response.status_code == 422
