from __future__ import annotations

from fastapi import APIRouter, File, Response, UploadFile, status

from app.core.deps import DbSession, TeacherUser
from app.schemas.question import UploadedImageResponse
from app.services.upload_service import UploadService

router = APIRouter(prefix="/questions", tags=["questions"])


@router.post(
    "/upload-image",
    response_model=UploadedImageResponse,
    summary="Upload an image for a question or an option (teacher)",
)
async def upload_image(
    current_user: TeacherUser, db: DbSession, file: UploadFile = File(...)
):
    """The returned ``url`` is what goes into ``question_image_url`` or
    ``option_image_url``. The file is decoded before it is stored, so a mislabelled
    upload is rejected rather than served back later (docs/security.md §7)."""
    stored = await UploadService(db).save_image(file, current_user)
    return UploadedImageResponse(
        url=stored.url, width=stored.width, height=stored.height, bytes=stored.bytes
    )


@router.delete(
    "/upload-image/{name}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete an uploaded image that no question uses (uploader or admin)",
)
def delete_image(name: str, current_user: TeacherUser, db: DbSession) -> Response:
    """Refuses with 409 while any question or option still points at it.

    The reference is a URL string rather than a foreign key, so nothing else would stop
    a published paper losing its diagram to a tidy-up.
    """
    UploadService(db).delete(name, current_user)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
