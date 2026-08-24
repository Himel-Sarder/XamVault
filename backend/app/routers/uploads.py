from __future__ import annotations

from fastapi import APIRouter, File, UploadFile

from app.core.deps import TeacherUser
from app.schemas.question import UploadedImageResponse
from app.services.upload_service import UploadService

router = APIRouter(prefix="/questions", tags=["questions"])


@router.post(
    "/upload-image",
    response_model=UploadedImageResponse,
    summary="Upload an image for a question or an option (teacher)",
)
async def upload_image(current_user: TeacherUser, file: UploadFile = File(...)):
    """The returned ``url`` is what goes into ``question_image_url`` or
    ``option_image_url``. The file is decoded before it is stored, so a mislabelled
    upload is rejected rather than served back later (docs/security.md §7)."""
    stored = await UploadService().save_image(file)
    return UploadedImageResponse(
        url=stored.url, width=stored.width, height=stored.height, bytes=stored.bytes
    )
