"""The disk-to-database migration for images uploaded before the storage changed."""

from __future__ import annotations

import pytest

from app.models.question import Question
from app.models.upload import UploadedImage
from app.utils.import_uploads import import_uploads
from tests.conftest import png_bytes


@pytest.fixture
def folder(tmp_path):
    return tmp_path


def test_a_file_keeps_its_id_so_existing_questions_resolve(db, admin, folder):
    """The whole point: questions already store /uploads/<id>.png.

    Generating a fresh id would mean rewriting every question that referred to it, and
    any one missed would be a silently blank diagram in a paper.
    """
    (folder / "abc123.png").write_bytes(png_bytes())

    report = import_uploads(db, folder, commit=True)

    assert report.imported == ["abc123.png"]
    stored = db.get(UploadedImage, "abc123")
    assert stored is not None
    assert stored.url == "/uploads/abc123.png"
    assert stored.data == png_bytes()
    assert stored.content_type == "image/png"


def test_running_it_twice_changes_nothing(db, admin, folder):
    (folder / "abc123.png").write_bytes(png_bytes())
    import_uploads(db, folder, commit=True)

    second = import_uploads(db, folder, commit=True)
    assert second.imported == []
    assert second.skipped == ["abc123.png"]
    assert db.query(UploadedImage).count() == 1


def test_a_dry_run_writes_nothing(db, admin, folder):
    (folder / "abc123.png").write_bytes(png_bytes())

    report = import_uploads(db, folder, commit=False)
    assert report.imported == ["abc123.png"]
    assert db.query(UploadedImage).count() == 0


def test_a_file_that_is_not_an_image_is_reported_not_raised(db, admin, folder):
    (folder / "notes.png").write_bytes(b"#!/bin/sh\nrm -rf /\n")
    (folder / "real.png").write_bytes(png_bytes())

    report = import_uploads(db, folder, commit=True)
    # One bad file must not stop the rest from being carried across.
    assert report.unreadable == ["notes.png"]
    assert report.imported == ["real.png"]


def test_dotfiles_are_not_treated_as_failed_images(db, admin, folder):
    (folder / ".gitkeep").write_text("")

    report = import_uploads(db, folder, commit=True)
    assert report.unreadable == []
    assert report.imported == []


def test_a_file_no_question_refers_to_is_carried_and_flagged(db, admin, folder):
    (folder / "spare.png").write_bytes(png_bytes())

    report = import_uploads(db, folder, commit=True)
    # A teacher replaced an image and the old one was never cleaned up. Deciding from
    # here that it is rubbish would be a guess, so it is kept and marked.
    assert report.imported == ["spare.png"]
    assert report.orphaned == ["spare.png"]


def test_an_image_a_question_needs_but_disk_lacks_is_named(db, admin, teacher, folder):
    """The ones that cannot be recovered are the ones worth naming.

    Left silent, they become blank diagrams nobody knows to re-upload.
    """
    db.add(
        Question(
            created_by=teacher.id,
            type="IMAGE_TEXT_OPTIONS",
            question_text="What does this show?",
            question_image_url="/uploads/gone.png",
            marks=5,
        )
    )
    db.commit()

    report = import_uploads(db, folder, commit=True)
    assert report.missing == ["/uploads/gone.png"]


def test_it_refuses_rather_than_guessing_an_uploader(db, folder):
    (folder / "abc123.png").write_bytes(png_bytes())

    # The column is NOT NULL. Inventing an owner would misattribute the file.
    with pytest.raises(RuntimeError, match="admin"):
        import_uploads(db, folder, commit=True)
