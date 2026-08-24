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


def test_the_stored_name_is_server_generated(client, api, auth_headers, teacher, upload_dir):
    """The client's filename is never used as a path component, which is what makes
    traversal impossible rather than merely unlikely."""
    response = _upload(
        client, api, auth_headers(teacher), png_bytes(), name="../../etc/passwd.png"
    )

    assert response.status_code == 200
    url = response.json()["url"]
    assert ".." not in url
    assert "passwd" not in url
    stored = list(upload_dir.iterdir())
    assert len(stored) == 1
    assert stored[0].name == url.removeprefix("/uploads/")


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
