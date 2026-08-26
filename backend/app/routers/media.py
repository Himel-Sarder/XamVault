from __future__ import annotations

from fastapi import APIRouter, Response

from app.core.deps import DbSession
from app.services.upload_service import UploadService

#: Mounted at the server root rather than under ``/api/v1``: these URLs are stored on
#: questions and rendered by an ``<img>``, so they should not carry an API version that
#: would strand every saved reference the day the version changes.
router = APIRouter(tags=["media"])


@router.get(
    "/uploads/{name}",
    summary="Serve an uploaded question image",
    response_class=Response,
)
def read_image(name: str, db: DbSession) -> Response:
    """Deliberately unauthenticated.

    An image widget cannot attach a bearer token, and requiring one would mean no
    question image ever renders. What is served is a diagram chosen by a teacher for a
    paper, addressed by a random 32-character id that is not guessable and not
    enumerable — the same reasoning that lets any site serve its own media.

    The correct answer, the marks and every judgement about a student remain behind
    authentication, which is where the sensitivity actually is.
    """
    image = UploadService(db).get(name)
    return Response(
        content=image.data,
        media_type=image.content_type,
        headers={
            # The id is a content address: a given id always holds the same bytes,
            # because replacing an image uploads a new one. So it can be cached hard.
            "Cache-Control": "public, max-age=31536000, immutable",
            "Content-Length": str(image.byte_size),
        },
    )
