"""Validated image upload (§20, §49).

An uploaded file is accepted only when *every* check passes. The important one is that
the image is actually decoded: a file called ``diagram.png`` whose bytes are a shell
script fails here, where trusting the extension or the ``Content-Type`` header would let
it through (docs/security.md §7).
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass

from fastapi import UploadFile
from PIL import Image, UnidentifiedImageError
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import ConflictError, InvalidRequestError, NotFoundError
from app.models.question import Question, QuestionOption
from app.models.upload import UploadedImage
from app.models.user import User

# Formats Pillow must report after decoding, mapped to the extension we store under.
ALLOWED_FORMATS: dict[str, str] = {
    "PNG": ".png",
    "JPEG": ".jpg",
    "GIF": ".gif",
    "WEBP": ".webp",
}

MIN_DIMENSION = 16
MAX_DIMENSION = 4096

# Read in chunks so an oversized upload is rejected without ever being held in memory.
CHUNK_SIZE = 64 * 1024


# What each accepted format is served back as. Taken from what Pillow decoded, never
# from the filename or the Content-Type header the client sent.
CONTENT_TYPES: dict[str, str] = {
    "PNG": "image/png",
    "JPEG": "image/jpeg",
    "GIF": "image/gif",
    "WEBP": "image/webp",
}


@dataclass(frozen=True, slots=True)
class StoredImage:
    url: str
    width: int
    height: int
    bytes: int


class UploadService:
    """Stores images in the database.

    Not on disk: the deployment target has no persistent volume, so a file written to
    the container is lost when the instance is replaced. See :class:`UploadedImage` for
    the reasoning and the intended migration path.
    """

    def __init__(self, db: Session) -> None:
        self.db = db

    async def save_image(self, upload: UploadFile, uploader: User) -> StoredImage:
        payload = await self._read_within_limit(upload)
        image_format, width, height = self._decode(payload)

        # The client's filename is never used anywhere in the address, which is what
        # makes traversal impossible rather than merely unlikely.
        image = UploadedImage(
            id=uuid.uuid4().hex,
            content_type=CONTENT_TYPES[image_format],
            extension=ALLOWED_FORMATS[image_format],
            width=width,
            height=height,
            byte_size=len(payload),
            data=payload,
            uploaded_by=uploader.id,
        )
        self.db.add(image)
        self.db.commit()

        return StoredImage(
            url=image.url, width=width, height=height, bytes=len(payload)
        )

    def get(self, name: str) -> UploadedImage:
        """Looks an image up by the filename part of its URL."""
        image_id = name.rsplit(".", 1)[0]
        image = self.db.get(UploadedImage, image_id)
        if image is None:
            raise NotFoundError("Image not found")
        return image

    def delete(self, name: str, actor: User) -> None:
        """Removes an image, unless a question still points at it.

        The reference is a URL string rather than a foreign key, so the database will
        not stop this on its own. Checking here is what keeps a published paper from
        losing its diagram because someone tidied up an upload they thought was spare.
        """
        image = self.get(name)
        if not (actor.is_admin or image.uploaded_by == actor.id):
            # Not yours, and whether it exists is not your business either.
            raise NotFoundError("Image not found")

        url = image.url
        in_use = self.db.execute(
            select(func.count())
            .select_from(Question)
            .where(Question.question_image_url == url)
        ).scalar_one() + self.db.execute(
            select(func.count())
            .select_from(QuestionOption)
            .where(QuestionOption.option_image_url == url)
        ).scalar_one()
        if in_use:
            raise ConflictError(
                "This image is still used by a question, so it was not deleted. "
                "Remove it from the question first.",
                code="image_in_use",
            )

        self.db.delete(image)
        self.db.commit()

    async def _read_within_limit(self, upload: UploadFile) -> bytes:
        limit = settings.max_upload_size_bytes
        chunks: list[bytes] = []
        total = 0
        while chunk := await upload.read(CHUNK_SIZE):
            total += len(chunk)
            if total > limit:
                raise InvalidRequestError(
                    f"Image is larger than {settings.MAX_UPLOAD_SIZE_MB} MB",
                    code="file_too_large",
                )
            chunks.append(chunk)
        if total == 0:
            raise InvalidRequestError("The uploaded file is empty", code="empty_file")
        return b"".join(chunks)

    @staticmethod
    def _decode(payload: bytes) -> tuple[str, int, int]:
        import io

        try:
            with Image.open(io.BytesIO(payload)) as image:
                image_format = image.format or ""
                width, height = image.size
                # verify() catches truncated and malformed files that open() accepts.
                image.verify()
        except (UnidentifiedImageError, OSError, ValueError) as exc:
            raise InvalidRequestError(
                "That file is not a readable image", code="not_an_image"
            ) from exc

        if image_format not in ALLOWED_FORMATS:
            allowed = ", ".join(sorted(ALLOWED_FORMATS))
            raise InvalidRequestError(
                f"Unsupported image format. Allowed: {allowed}", code="unsupported_format"
            )
        if not (MIN_DIMENSION <= width <= MAX_DIMENSION and MIN_DIMENSION <= height <= MAX_DIMENSION):
            raise InvalidRequestError(
                f"Image dimensions must be between {MIN_DIMENSION} and {MAX_DIMENSION} pixels",
                code="bad_dimensions",
            )
        return image_format, width, height
