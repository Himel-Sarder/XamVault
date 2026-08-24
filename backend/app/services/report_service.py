"""Phase 18 — exported reports (§47, §48).

Both formats are built in memory and streamed; nothing is written to disk, so there are
no temporary files to clean up or to leak between requests.

A report is a *rendering* of data the caller may already read through the API — the same
ownership checks apply, and nothing appears in a report that the caller could not have
fetched as JSON.
"""

from __future__ import annotations

import io
from datetime import UTC, datetime
from typing import Any

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import (
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import NotFoundError
from app.models.exam import Exam
from app.models.result import Result
from app.models.user import User
from app.repositories.attempt_repository import AttemptRepository
from app.repositories.exam_repository import ExamRepository

HEADER_FILL = PatternFill("solid", fgColor="1B5E9B")
BRAND = colors.HexColor("#1B5E9B")


def _fmt(value: float | None) -> str:
    if value is None:
        return "—"
    return f"{value:.0f}" if float(value) % 1 == 0 else f"{value:.2f}"


def _safe_filename(text: str) -> str:
    """A filename the browser and the filesystem will both accept."""
    keep = [c if c.isalnum() or c in "-_" else "-" for c in text]
    return "".join(keep).strip("-")[:60] or "report"


class ReportService:
    def __init__(self, db: Session) -> None:
        self.db = db
        self.exams = ExamRepository(db)
        self.attempts = AttemptRepository(db)

    # --------------------------------------------------------- authorization

    def _owned_exam(self, exam_id: int, actor: User) -> Exam:
        exam = self.exams.get(exam_id)
        if exam is None:
            raise NotFoundError("Exam not found")
        if actor.is_admin or exam.teacher_id == actor.id:
            return exam
        raise NotFoundError("Exam not found")

    def _readable_result(self, result_id: int, actor: User) -> Result:
        result = self.attempts.get_result(result_id)
        if result is None:
            raise NotFoundError("Result not found")

        if actor.is_student:
            # A student may print their own result, and only once it is released —
            # exactly the rule the JSON endpoint applies.
            if result.student_id != actor.id or not result.is_published:
                raise NotFoundError("Result not found")
            return result

        self._owned_exam(result.exam_id, actor)
        return result

    # ------------------------------------------------------------------ rows

    def _rows(self, exam_id: int) -> list[dict[str, Any]]:
        rows: list[dict[str, Any]] = []
        for result in self.attempts.list_results_for_exam(exam_id):
            profile = result.student.student_profile
            rows.append(
                {
                    "student_number": profile.student_id if profile else result.student.user_id,
                    "name": result.student.name,
                    "mcq": float(result.mcq_score),
                    "short": float(result.short_answer_score),
                    "code": float(result.code_score),
                    "total": float(result.total_score),
                    "percentage": float(result.percentage),
                    "status": result.status,
                }
            )
        return rows

    # ------------------------------------------------------------------- PDF

    def exam_pdf(self, exam_id: int, actor: User) -> tuple[bytes, str]:
        exam = self._owned_exam(exam_id, actor)
        rows = self._rows(exam_id)
        percentages = [row["percentage"] for row in rows]

        buffer = io.BytesIO()
        doc = SimpleDocTemplate(
            buffer,
            pagesize=A4,
            title=f"{exam.title} - results",
            author=settings.UNIVERSITY_NAME,
            leftMargin=18 * mm,
            rightMargin=18 * mm,
            topMargin=18 * mm,
            bottomMargin=18 * mm,
        )
        styles = getSampleStyleSheet()
        heading = ParagraphStyle(
            "Heading", parent=styles["Title"], fontSize=16, textColor=BRAND, spaceAfter=2
        )
        subtle = ParagraphStyle(
            "Subtle", parent=styles["Normal"], fontSize=9, textColor=colors.grey
        )

        story: list[Any] = [
            Paragraph(settings.UNIVERSITY_NAME, heading),
            Paragraph(exam.course.department.name if exam.course.department else "-", subtle),
            Spacer(1, 8 * mm),
            Paragraph(f"<b>{exam.title}</b>", styles["Heading2"]),
            Paragraph(
                f"{exam.course.course_code} - {exam.course.course_name}<br/>"
                f"Teacher: {exam.teacher.name}<br/>"
                f"Total marks: {exam.total_marks}<br/>"
                f"Generated: {datetime.now(UTC).strftime('%d %b %Y %H:%M UTC')}",
                styles["Normal"],
            ),
            Spacer(1, 6 * mm),
        ]

        if not rows:
            story.append(
                Paragraph("No student has submitted this exam yet.", styles["Normal"])
            )
        else:
            table_data = [
                ["Student ID", "Name", "MCQ", "Short", "Code", "Total", "%", "Status"]
            ]
            for row in rows:
                table_data.append([
                    row["student_number"],
                    row["name"],
                    _fmt(row["mcq"]),
                    _fmt(row["short"]),
                    _fmt(row["code"]),
                    f"{_fmt(row['total'])}/{exam.total_marks}",
                    f"{row['percentage']:.1f}",
                    row["status"],
                ])
            table = Table(table_data, repeatRows=1, hAlign="LEFT")
            table.setStyle(TableStyle([
                ("BACKGROUND", (0, 0), (-1, 0), BRAND),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("FONTSIZE", (0, 0), (-1, -1), 8),
                ("ALIGN", (2, 0), (-1, -1), "RIGHT"),
                ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#CCCCCC")),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1),
                 [colors.white, colors.HexColor("#F4F6F8")]),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]))
            story += [table, Spacer(1, 6 * mm)]

            average = sum(percentages) / len(percentages)
            summary = Table(
                [
                    ["Submitted", "Average", "Highest", "Lowest"],
                    [
                        str(len(rows)),
                        f"{average:.1f}%",
                        f"{max(percentages):.1f}%",
                        f"{min(percentages):.1f}%",
                    ],
                ],
                hAlign="LEFT",
            )
            summary.setStyle(TableStyle([
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("FONTSIZE", (0, 0), (-1, -1), 9),
                ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#CCCCCC")),
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#EEF2F6")),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]))
            story.append(summary)

        doc.build(story)
        filename = (
            f"{_safe_filename(exam.course.course_code)}-"
            f"{_safe_filename(exam.title)}-results.pdf"
        )
        return buffer.getvalue(), filename

    def result_pdf(self, result_id: int, actor: User) -> tuple[bytes, str]:
        """One student's transcript for a single exam (§47)."""
        result = self._readable_result(result_id, actor)
        exam = result.exam
        profile = result.student.student_profile

        buffer = io.BytesIO()
        doc = SimpleDocTemplate(
            buffer,
            pagesize=A4,
            title=f"{exam.title} - {result.student.name}",
            author=settings.UNIVERSITY_NAME,
            leftMargin=18 * mm,
            rightMargin=18 * mm,
            topMargin=18 * mm,
            bottomMargin=18 * mm,
        )
        styles = getSampleStyleSheet()
        heading = ParagraphStyle(
            "Heading", parent=styles["Title"], fontSize=16, textColor=BRAND, spaceAfter=2
        )
        subtle = ParagraphStyle(
            "Subtle", parent=styles["Normal"], fontSize=9, textColor=colors.grey
        )

        submitted = result.attempt.submitted_at
        detail = Table(
            [
                ["Student", result.student.name],
                ["Student ID", profile.student_id if profile else result.student.user_id],
                ["Course", f"{exam.course.course_code} - {exam.course.course_name}"],
                ["Exam", exam.title],
                ["Submitted", submitted.strftime("%d %b %Y %H:%M UTC") if submitted else "-"],
            ],
            colWidths=[35 * mm, 120 * mm],
            hAlign="LEFT",
        )
        detail.setStyle(TableStyle([
            ("FONTSIZE", (0, 0), (-1, -1), 9),
            ("TEXTCOLOR", (0, 0), (0, -1), colors.grey),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ]))

        marks = Table(
            [
                ["Component", "Marks"],
                ["Multiple choice", _fmt(float(result.mcq_score))],
                ["Short answer", _fmt(float(result.short_answer_score))],
                ["Code", _fmt(float(result.code_score))],
                ["Total", f"{_fmt(float(result.total_score))} / {exam.total_marks}"],
                ["Percentage", f"{float(result.percentage):.1f}%"],
            ],
            colWidths=[60 * mm, 40 * mm],
            hAlign="LEFT",
        )
        marks.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, 0), BRAND),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
            ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
            ("FONTNAME", (0, -2), (-1, -1), "Helvetica-Bold"),
            ("FONTSIZE", (0, 0), (-1, -1), 9),
            ("ALIGN", (1, 0), (-1, -1), "RIGHT"),
            ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#CCCCCC")),
            ("TOPPADDING", (0, 0), (-1, -1), 4),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ]))

        doc.build([
            Paragraph(settings.UNIVERSITY_NAME, heading),
            Paragraph(exam.course.department.name if exam.course.department else "-", subtle),
            Spacer(1, 8 * mm),
            Paragraph("<b>Statement of result</b>", styles["Heading2"]),
            Spacer(1, 3 * mm),
            detail,
            Spacer(1, 6 * mm),
            marks,
        ])
        filename = (
            f"{_safe_filename(exam.course.course_code)}-"
            f"{_safe_filename(result.student.name)}-result.pdf"
        )
        return buffer.getvalue(), filename

    # ----------------------------------------------------------------- Excel

    def exam_excel(self, exam_id: int, actor: User) -> tuple[bytes, str]:
        """The column set from §48, as a real spreadsheet rather than a CSV renamed."""
        exam = self._owned_exam(exam_id, actor)
        rows = self._rows(exam_id)

        workbook = Workbook()
        sheet = workbook.active
        sheet.title = "Results"

        sheet["A1"] = settings.UNIVERSITY_NAME
        sheet["A1"].font = Font(bold=True, size=14)
        sheet["A2"] = f"{exam.course.course_code} - {exam.title}"
        sheet["A3"] = (
            f"Teacher: {exam.teacher.name}    Total marks: {exam.total_marks}    "
            f"Generated: {datetime.now(UTC).strftime('%d %b %Y %H:%M UTC')}"
        )
        sheet["A3"].font = Font(size=9, color="666666")

        headers = [
            "Student ID",
            "Student Name",
            "MCQ Score",
            "Short Answer Score",
            "Code Score",
            "Total Score",
            "Percentage",
            "Status",
        ]
        header_row = 5
        for column, title in enumerate(headers, start=1):
            cell = sheet.cell(row=header_row, column=column, value=title)
            cell.font = Font(bold=True, color="FFFFFF")
            cell.fill = HEADER_FILL
            cell.alignment = Alignment(horizontal="center", vertical="center")

        for offset, row in enumerate(rows, start=header_row + 1):
            # Numbers are written as numbers, not strings: a spreadsheet nobody can sum
            # is not much of an export.
            sheet.cell(row=offset, column=1, value=row["student_number"])
            sheet.cell(row=offset, column=2, value=row["name"])
            sheet.cell(row=offset, column=3, value=row["mcq"])
            sheet.cell(row=offset, column=4, value=row["short"])
            sheet.cell(row=offset, column=5, value=row["code"])
            sheet.cell(row=offset, column=6, value=row["total"])
            percentage = sheet.cell(row=offset, column=7, value=row["percentage"] / 100)
            percentage.number_format = "0.0%"
            sheet.cell(row=offset, column=8, value=row["status"])

        widths = [14, 28, 12, 20, 12, 12, 12, 12]
        for column, width in enumerate(widths, start=1):
            sheet.column_dimensions[get_column_letter(column)].width = width
        # The header stays visible when a long cohort is scrolled.
        sheet.freeze_panes = sheet.cell(row=header_row + 1, column=1)

        buffer = io.BytesIO()
        workbook.save(buffer)
        filename = (
            f"{_safe_filename(exam.course.course_code)}-"
            f"{_safe_filename(exam.title)}-results.xlsx"
        )
        return buffer.getvalue(), filename
