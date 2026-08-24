"""Validated image upload (§20, §49).

An uploaded file is accepted only when *every* check passes. The important one is that
the image is actually decoded: a file called ``diagram.png`` whose bytes are a shell
script fails here, where trusting the extension or the ``Content-Type`` header would let
it through (docs/security.md §7).
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from pathlib import Path

from fastapi import UploadFile
from PIL import Image, UnidentifiedImageError

from app.core.config import settings
from app.core.exceptions import InvalidRequestError

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


@dataclass(frozen=True, slots=True)
class StoredImage:
    url: str
    width: int
    height: int
    bytes: int


class UploadService:
    def __init__(self, directory: Path | None = None) -> None:
        self.directory = directory or settings.upload_path
        self.directory.mkdir(parents=True, exist_ok=True)

    async def save_image(self, upload: UploadFile) -> StoredImage:
        payload = await self._read_within_limit(upload)
        image_format, width, height = self._decode(payload)

        # The client's filename is never used as a path component, which is what makes
        # traversal impossible rather than merely unlikely.
        name = f"{uuid.uuid4().hex}{ALLOWED_FORMATS[image_format]}"
        (self.directory / name).write_bytes(payload)

        return StoredImage(
            url=f"/uploads/{name}", width=width, height=height, bytes=len(payload)
        )

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
