"""Move images off the disk and into the database.

    python -m app.utils.import_uploads            # report what would happen
    python -m app.utils.import_uploads --commit   # do it

Images used to be written to ``UPLOAD_DIR`` and served by a static mount. They are rows
in ``uploaded_images`` now, because the deployment target has no persistent disk and a
file written to the container does not survive the instance being replaced.

That change fixed new uploads and left the old ones stranded: a question still refers to
``/uploads/<id>.png``, nothing serves it any more, and the student sees "Image could not
be loaded". This carries the surviving files across **keeping each file's id**, so the
URLs already stored on questions resolve without touching a single question row.

It is deliberately idempotent and additive. An id already in the table is skipped rather
than overwritten, so running it twice is safe and running it against a database that has
moved on cannot clobber anything.

What it cannot do is recover a file that was only ever on a wiped container. Those are
reported by name so they can be re-uploaded deliberately, rather than left as silent
gaps in a paper.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass, field
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import SessionLocal
from app.models.question import Question, QuestionOption
from app.models.upload import UploadedImage
from app.models.user import User
from app.services.upload_service import ALLOWED_FORMATS, CONTENT_TYPES, UploadService


@dataclass(slots=True)
class ImportReport:
    imported: list[str] = field(default_factory=list)
    skipped: list[str] = field(default_factory=list)
    unreadable: list[str] = field(default_factory=list)

    #: Carried across although no question points at them.
    orphaned: list[str] = field(default_factory=list)

    #: Referenced by a question, but the file is not here to carry.
    missing: list[str] = field(default_factory=list)


def _referenced_urls(db: Session) -> set[str]:
    """Every image URL a question or option currently points at."""
    urls: set[str] = set()
    for column in (Question.question_image_url, QuestionOption.option_image_url):
        urls.update(
            value
            for (value,) in db.execute(select(column).where(column.is_not(None)))
            if value
        )
    return urls


def import_uploads(db: Session, directory: Path, *, commit: bool) -> ImportReport:
    """The whole of the work, with the session passed in so it can be tested."""
    report = ImportReport()
    if not directory.is_dir():
        return report

    # An uploader is required by the schema. Any admin will do: this records who carried
    # the file across, not who originally chose it, and pretending to know the latter
    # would be worse than being plainly wrong about it.
    uploader = (
        db.execute(select(User).where(User.role == "admin").order_by(User.id))
        .scalars()
        .first()
    )
    if uploader is None:
        raise RuntimeError("No admin account to attribute the import to.")

    referenced = _referenced_urls(db)

    for path in sorted(directory.iterdir()):
        # .gitkeep and its kind are not failed images, and reporting them as such buries
        # the one line that matters in noise.
        if not path.is_file() or path.name.startswith("."):
            continue

        image_id = path.stem
        url = f"/uploads/{path.name}"

        if db.get(UploadedImage, image_id) is not None:
            report.skipped.append(path.name)
            continue

        payload = path.read_bytes()
        try:
            image_format, width, height = UploadService._decode(payload)
        except Exception:  # noqa: BLE001 - report it and carry on with the rest
            report.unreadable.append(path.name)
            continue

        if url not in referenced:
            # Not an error: a teacher replaced an image and the old one was never
            # cleaned up. Carried across anyway — it is small, and deciding from here
            # that it is rubbish would be a guess.
            report.orphaned.append(path.name)

        if commit:
            db.add(
                UploadedImage(
                    id=image_id,
                    content_type=CONTENT_TYPES[image_format],
                    extension=ALLOWED_FORMATS[image_format],
                    width=width,
                    height=height,
                    byte_size=len(payload),
                    data=payload,
                    uploaded_by=uploader.id,
                )
            )
        report.imported.append(path.name)

    if commit:
        db.commit()

    report.missing = sorted(
        url for url in referenced if not (directory / Path(url).name).exists()
    )
    return report


def main(argv: list[str]) -> int:
    from app.core.config import settings

    commit = "--commit" in argv
    directory = (
        Path(argv[argv.index("--dir") + 1]) if "--dir" in argv else settings.upload_path
    )

    db = SessionLocal()
    try:
        report = import_uploads(db, directory, commit=commit)
    except RuntimeError as error:
        print(error)
        return 1
    finally:
        db.close()

    for name in report.imported:
        mark = "*" if name in report.orphaned else " "
        print(f"  import{mark} {name}")
    for name in report.skipped:
        print(f"  skip    {name}  already in the database")
    for name in report.unreadable:
        print(f"  FAILED  {name}  not a readable image")

    print()
    print(
        f"{len(report.imported)} to import "
        f"({len(report.orphaned)} not referenced by any question)"
    )
    print(f"{len(report.skipped)} already present, {len(report.unreadable)} unreadable")

    if report.missing:
        print()
        print(f"{len(report.missing)} referenced by a question but not on disk:")
        for url in report.missing:
            print(f"  {url}")
        print("These were only ever on a container that has since been replaced.")
        print("They cannot be recovered here and need re-uploading.")

    if not commit:
        print()
        print("Dry run. Re-run with --commit to write.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
