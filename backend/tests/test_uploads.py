"""Phase 5 — image upload validation (§20, §49)."""

from __future__ import annotations

from tests.conftest import png_bytes


def _upload(client, api, headers, content: bytes, name: str = "diagram.png",
            content_type: str = "image/png"):
    return client.post(
        f"{api}/questions/upload-image",
        headers=headers,
        files={"file": (name, content, content_type)},
    )


def test_a_teacher_can_upload_an_image(client, api, auth_headers, teacher, upload_dir):
    response = _upload(client, api, auth_headers(teacher), png_bytes(120, 80))

    assert response.status_code == 200
    body = response.json()
    assert body["width"] == 120
    assert body["height"] == 80
    assert body["url"].startswith("/uploads/")
    assert body["url"].endswith(".png")


def test_the_stored_name_is_server_generated(
    client, api, auth_headers, teacher, upload_dir, db
):
    """The client's filename is never used as a path component, which is what makes
    traversal impossible rather than merely unlikely."""
    response = _upload(
        client, api, auth_headers(teacher), png_bytes(), name="../../etc/passwd.png"
    )

    assert response.status_code == 200
    url = response.json()["url"]
    assert ".." not in url
    assert "passwd" not in url

    # Addressed by a server-generated id, and holding the bytes we sent.
    from app.models.upload import UploadedImage

    stored = db.query(UploadedImage).all()
    assert len(stored) == 1
    assert url == f"/uploads/{stored[0].id}{stored[0].extension}"
    assert stored[0].data == png_bytes()


def test_a_file_that_is_not_an_image_is_rejected(client, api, auth_headers, teacher, upload_dir):
    # Correct extension, correct Content-Type, wrong bytes: only decoding catches this.
    response = _upload(
        client, api, auth_headers(teacher), b"#!/bin/sh\nrm -rf /\n", name="diagram.png"
    )

    assert response.status_code == 400
    assert response.json()["code"] == "not_an_image"
    assert list(upload_dir.iterdir()) == []


def test_an_empty_file_is_rejected(client, api, auth_headers, teacher, upload_dir):
    response = _upload(client, api, auth_headers(teacher), b"")
    assert response.status_code == 400
    assert response.json()["code"] == "empty_file"


def test_an_oversized_image_is_rejected(client, api, auth_headers, teacher, upload_dir, monkeypatch):
    from app.core.config import settings as app_settings

    monkeypatch.setattr(app_settings, "MAX_UPLOAD_SIZE_MB", 0.001)
    response = _upload(client, api, auth_headers(teacher), png_bytes(400, 400))

    assert response.status_code == 400
    assert response.json()["code"] == "file_too_large"


def test_dimensions_outside_the_allowed_range_are_rejected(
    client, api, auth_headers, teacher, upload_dir
):
    response = _upload(client, api, auth_headers(teacher), png_bytes(4, 4))
    assert response.status_code == 400
    assert response.json()["code"] == "bad_dimensions"


def test_students_cannot_upload(client, api, auth_headers, student, upload_dir):
    assert _upload(client, api, auth_headers(student), png_bytes()).status_code == 403


def test_anonymous_uploads_are_refused(client, api, upload_dir):
    response = client.post(
        f"{api}/questions/upload-image",
        files={"file": ("d.png", png_bytes(), "image/png")},
    )
    assert response.status_code == 401


# ------------------------------------------------- serving it back, and removing it


def _upload_one(client, api, headers):
    return _upload(client, api, headers, png_bytes()).json()["url"]


def test_an_uploaded_image_can_actually_be_fetched_back(
    client, api, auth_headers, teacher, upload_dir
):
    """The bug this was written for.

    Uploading always worked; serving was mounted only when ENV was not production, so
    on the deployed app every question image returned 404 while development was fine.
    """
    url = _upload_one(client, api, auth_headers(teacher))

    response = client.get(url)
    assert response.status_code == 200
    assert response.headers["content-type"] == "image/png"
    assert response.content == png_bytes()


def test_an_image_is_served_the_same_way_in_production(
    client, api, auth_headers, teacher, upload_dir, monkeypatch
):
    from app.core.config import settings as app_settings

    monkeypatch.setattr(app_settings, "ENV", "production")
    url = _upload_one(client, api, auth_headers(teacher))
    # Dev and production take the same path now; there is no environment in which a
    # question image silently stops rendering.
    assert client.get(url).status_code == 200


def test_an_image_widget_needs_no_token(client, api, auth_headers, teacher, upload_dir):
    """An <img> cannot attach a bearer token, so requiring one would mean no question
    image ever renders. The id is random and unguessable; the marks stay behind auth."""
    url = _upload_one(client, api, auth_headers(teacher))
    assert client.get(url).status_code == 200


def test_an_unknown_image_is_not_found(client, api):
    assert client.get("/uploads/deadbeefdeadbeefdeadbeefdeadbeef.png").status_code == 404


def test_an_unused_image_can_be_deleted(client, api, auth_headers, teacher, upload_dir):
    url = _upload_one(client, api, auth_headers(teacher))
    name = url.removeprefix("/uploads/")

    assert client.delete(
        f"{api}/questions/upload-image/{name}", headers=auth_headers(teacher)
    ).status_code == 204
    assert client.get(url).status_code == 404


def test_an_image_a_question_uses_is_not_deleted(
    client, api, auth_headers, teacher, teacher_course, make_exam, upload_dir
):
    """The reference is a URL string, not a foreign key, so nothing else would stop a
    published paper losing its diagram to a tidy-up."""
    url = _upload_one(client, api, auth_headers(teacher))
    exam = make_exam(teacher, teacher_course)
    created = client.post(
        f"{api}/exams/{exam.id}/questions",
        headers=auth_headers(teacher),
        json={
            "question_type": "image_text_options",
            "question_text": "What does this show?",
            "question_image_url": url,
            "marks": 5,
            "options": [
                {"option_text": "A", "is_correct": True},
                {"option_text": "B", "is_correct": False},
            ],
        },
    )
    assert created.status_code == 201, created.text

    response = client.delete(
        f"{api}/questions/upload-image/{url.removeprefix('/uploads/')}",
        headers=auth_headers(teacher),
    )
    assert response.status_code == 409
    assert response.json()["code"] == "image_in_use"
    # And it is still there, which is the point.
    assert client.get(url).status_code == 200


def test_another_teacher_cannot_delete_my_image(
    client, api, auth_headers, teacher, other_teacher, upload_dir
):
    url = _upload_one(client, api, auth_headers(teacher))
    # 404, not 403: whether it exists is not their business either.
    assert client.delete(
        f"{api}/questions/upload-image/{url.removeprefix('/uploads/')}",
        headers=auth_headers(other_teacher),
    ).status_code == 404


def test_a_student_cannot_delete_images(client, api, auth_headers, teacher, student, upload_dir):
    url = _upload_one(client, api, auth_headers(teacher))
    assert client.delete(
        f"{api}/questions/upload-image/{url.removeprefix('/uploads/')}",
        headers=auth_headers(student),
    ).status_code == 403
