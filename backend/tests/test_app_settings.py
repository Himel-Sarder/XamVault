"""The handful of things an administrator sets about this installation."""

from __future__ import annotations


def test_the_default_is_the_configured_name(client, api, auth_headers, admin):
    """A fresh installation answers before anyone has opened the settings screen.

    The row is created lazily rather than seeded by the migration, so a database that
    predates the feature behaves exactly as it did before.
    """
    response = client.get(f"{api}/settings", headers=auth_headers(admin))

    assert response.status_code == 200
    assert response.json()["university_name"]


def test_an_admin_sets_the_university_name(client, api, auth_headers, admin):
    response = client.put(
        f"{api}/settings",
        headers=auth_headers(admin),
        json={"university_name": "Rajshahi University of Engineering & Technology"},
    )

    assert response.status_code == 200
    assert (
        response.json()["university_name"]
        == "Rajshahi University of Engineering & Technology"
    )


def test_it_survives_the_next_read(client, api, auth_headers, admin, teacher):
    client.put(
        f"{api}/settings",
        headers=auth_headers(admin),
        json={"university_name": "Khulna University"},
    )

    read = client.get(f"{api}/settings", headers=auth_headers(teacher))
    assert read.json()["university_name"] == "Khulna University"


def test_setting_it_twice_does_not_make_a_second_row(client, api, auth_headers, admin, db):
    from app.models.app_setting import AppSetting

    client.put(
        f"{api}/settings", headers=auth_headers(admin), json={"university_name": "One"}
    )
    client.put(
        f"{api}/settings", headers=auth_headers(admin), json={"university_name": "Two"}
    )

    db.expunge_all()
    assert db.query(AppSetting).count() == 1
    assert db.query(AppSetting).one().university_name == "Two"


def test_surrounding_and_doubled_whitespace_is_tidied(client, api, auth_headers, admin):
    """It is printed at the top of every report, where it would show."""
    response = client.put(
        f"{api}/settings",
        headers=auth_headers(admin),
        json={"university_name": "  Dhaka   University  "},
    )
    assert response.json()["university_name"] == "Dhaka University"


def test_an_empty_name_is_refused(client, api, auth_headers, admin):
    response = client.put(
        f"{api}/settings", headers=auth_headers(admin), json={"university_name": " "}
    )
    assert response.status_code == 422


def test_a_teacher_may_read_it_but_not_change_it(client, api, auth_headers, teacher):
    assert client.get(f"{api}/settings", headers=auth_headers(teacher)).status_code == 200
    assert (
        client.put(
            f"{api}/settings",
            headers=auth_headers(teacher),
            json={"university_name": "Not Theirs"},
        ).status_code
        == 403
    )


def test_a_student_may_read_it_but_not_change_it(client, api, auth_headers, student):
    assert client.get(f"{api}/settings", headers=auth_headers(student)).status_code == 200
    assert (
        client.put(
            f"{api}/settings",
            headers=auth_headers(student),
            json={"university_name": "Not Theirs"},
        ).status_code
        == 403
    )


def test_it_needs_signing_in(client, api):
    assert client.get(f"{api}/settings").status_code == 401
