from __future__ import annotations

from fastapi import APIRouter, Response

from app.core.deps import CurrentUser, DbSession, TeacherUser
from app.services.report_service import ReportService

router = APIRouter(prefix="/reports", tags=["reports"])

PDF = "application/pdf"
XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"


def _download(payload: bytes, filename: str, media_type: str) -> Response:
    """Content-Disposition names the file; the browser and the mobile client both use it
    rather than inventing a name from the URL."""
    return Response(
        content=payload,
        media_type=media_type,
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"',
            # The filename is the only header the client reads, and CORS hides response
            # headers it was not told to expose.
            "Access-Control-Expose-Headers": "Content-Disposition",
        },
    )


@router.get(
    "/exams/{exam_id}/pdf",
    summary="Results for one exam as a PDF (exam owner)",
    responses={200: {"content": {PDF: {}}, "description": "A PDF result sheet."}},
    response_class=Response,
)
def exam_pdf(exam_id: int, current_user: TeacherUser, db: DbSession) -> Response:
    payload, filename = ReportService(db).exam_pdf(exam_id, current_user)
    return _download(payload, filename, PDF)


@router.get(
    "/exams/{exam_id}/excel",
    summary="Results for one exam as a spreadsheet (exam owner)",
    responses={200: {"content": {XLSX: {}}, "description": "An .xlsx workbook."}},
    response_class=Response,
)
def exam_excel(exam_id: int, current_user: TeacherUser, db: DbSession) -> Response:
    payload, filename = ReportService(db).exam_excel(exam_id, current_user)
    return _download(payload, filename, XLSX)


@router.get(
    "/results/{result_id}/pdf",
    summary="One student's statement of result as a PDF",
    responses={200: {"content": {PDF: {}}, "description": "A PDF statement."}},
    response_class=Response,
)
def result_pdf(result_id: int, current_user: CurrentUser, db: DbSession) -> Response:
    """Open to both roles, under the rules each already has: the exam's owner may print
    any of its results; a student may print their own, once released."""
    payload, filename = ReportService(db).result_pdf(result_id, current_user)
    return _download(payload, filename, PDF)
