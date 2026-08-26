from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Body, Depends, Query, Response, status

from app.core.deps import CurrentUser, DbSession, StudentUser, TeacherUser
from app.models.exam import Exam, ExamQuestion
from app.schemas.common import Page, PageParams
from app.schemas.exam import (
    ExamCreate,
    ExamSettingsUpdate,
    ExamUpdate,
    PublishCheckResponse,
    StudentExamResponse,
    TeacherExamResponse,
)
from app.schemas.join_request import (
    BulkReviewRequest,
    BulkReviewResponse,
    JoinRequestResponse,
    JoinRequestStudent,
)
from app.schemas.attempt import AttemptResponse
from app.schemas.question import ExamQuestionResponse, QuestionCreate
from app.schemas.question_bank import AttachFromBankRequest
from app.schemas.analytics import ExamAnalytics
from app.schemas.grading import GradingQueueEntry
from app.schemas.result import PublishResultsResponse, TeacherResultResponse
from app.schemas.security import ExamSecuritySummary
from app.models.join_request import JoinRequest
from app.services.analytics_service import AnalyticsService
from app.services.attempt_service import AttemptService
from app.services.exam_service import ExamService
from app.services.security_service import SecurityService
from app.services.grading_service import GradingService
from app.services.question_bank_service import QuestionBankService
from app.services.join_request_service import JoinRequestService
from app.services.result_service import ResultService
from app.services.student_exam_service import StudentExamService

router = APIRouter(prefix="/exams", tags=["exams"])


def _exam_response(exam: Exam) -> TeacherExamResponse:
    # question_count and is_frozen are properties on the models, so the schemas read them
    # like any other attribute instead of the router patching them in afterwards.
    return TeacherExamResponse.model_validate(exam)


def _question_response(link: ExamQuestion) -> ExamQuestionResponse:
    return ExamQuestionResponse.model_validate(link)


def _join_request_response(request: JoinRequest) -> JoinRequestResponse:
    profile = request.student.student_profile
    return JoinRequestResponse(
        id=request.id,
        exam_id=request.exam_id,
        status=request.status,
        requested_at=request.requested_at,
        reviewed_at=request.reviewed_at,
        reviewed_by=request.reviewed_by,
        student=JoinRequestStudent(
            id=request.student.id,
            user_id=request.student.user_id,
            name=request.student.name,
            student_number=profile.student_id if profile else None,
        ),
    )


# ------------------------------------------------------------------ lifecycle


@router.post(
    "",
    response_model=TeacherExamResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a draft exam in one of my courses",
)
def create_exam(payload: ExamCreate, current_user: TeacherUser, db: DbSession):
    return _exam_response(ExamService(db).create(payload, current_user))


@router.get(
    "",
    response_model=None,
    summary="List exams — my own (teacher) or the ones available to me (student)",
    responses={
        200: {
            "description": "Page[TeacherExamResponse] for a teacher, "
            "Page[StudentExamResponse] for a student."
        }
    },
)
def list_exams(
    current_user: CurrentUser,
    db: DbSession,
    page: Annotated[PageParams, Depends()],
    course_id: Annotated[int | None, Query(description="Teacher only: filter to one course")] = None,
    exam_status: Annotated[
        str | None, Query(alias="status", description="Teacher only: draft, published, ...")
    ] = None,
    include_closed: Annotated[
        bool, Query(description="Student only: also list exams whose window has passed")
    ] = False,
) -> Page[TeacherExamResponse] | Page[StudentExamResponse]:
    """The response *class* differs by role, which is what keeps a student from ever
    receiving teacher-only fields — see docs/api.md §4. ``response_model`` is therefore
    left off and the correct schema is constructed explicitly."""
    if current_user.is_student:
        items, total = StudentExamService(db).list_available(
            current_user,
            offset=page.offset,
            limit=page.page_size,
            include_closed=include_closed,
        )
        return Page[StudentExamResponse](
            items=items, total=total, page=page.page, page_size=page.page_size
        )

    exams, total = ExamService(db).list_for_teacher(
        current_user,
        course_id=course_id,
        status=exam_status,
        offset=page.offset,
        limit=page.page_size,
    )
    return Page[TeacherExamResponse](
        items=[_exam_response(exam) for exam in exams],
        total=total,
        page=page.page,
        page_size=page.page_size,
    )


@router.get(
    "/{exam_id}",
    response_model=None,
    summary="Read an exam",
    responses={
        200: {
            "description": "TeacherExamResponse for the owning teacher, "
            "StudentExamResponse for an enrolled student."
        }
    },
)
def read_exam(
    exam_id: int, current_user: CurrentUser, db: DbSession
) -> TeacherExamResponse | StudentExamResponse:
    if current_user.is_student:
        return StudentExamService(db).get(exam_id, current_user)
    return _exam_response(ExamService(db).get_for_teacher(exam_id, current_user))


@router.patch("/{exam_id}", response_model=TeacherExamResponse, summary="Edit a draft exam")
def update_exam(
    exam_id: int, payload: ExamUpdate, current_user: TeacherUser, db: DbSession
):
    return _exam_response(ExamService(db).update(exam_id, payload, current_user))


@router.put(
    "/{exam_id}/settings",
    response_model=TeacherExamResponse,
    summary="Configure a draft exam",
)
def update_settings(
    exam_id: int, payload: ExamSettingsUpdate, current_user: TeacherUser, db: DbSession
):
    return _exam_response(ExamService(db).update_settings(exam_id, payload, current_user))


@router.post(
    "/{exam_id}/cancel",
    response_model=TeacherExamResponse,
    summary="Cancel an exam without losing what it produced (exam owner)",
)
def cancel_exam(exam_id: int, current_user: TeacherUser, db: DbSession) -> object:
    """For an exam students have already sat, where deleting would take their records
    with it. Attempts, answers and results all stay; no new sitting can begin."""
    return ExamService(db).cancel(exam_id, current_user)


@router.delete(
    "/{exam_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete an exam nobody has sat (exam owner)",
)
def delete_exam(exam_id: int, current_user: TeacherUser, db: DbSession) -> Response:
    ExamService(db).delete(exam_id, current_user)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# -------------------------------------------------------------------- publish


@router.get(
    "/{exam_id}/publish-check",
    response_model=PublishCheckResponse,
    summary="Why this exam can or cannot be published",
)
def publish_check(exam_id: int, current_user: TeacherUser, db: DbSession):
    issues = ExamService(db).publish_issues(exam_id, current_user)
    return PublishCheckResponse(can_publish=not issues, issues=issues)


@router.post(
    "/{exam_id}/publish",
    response_model=TeacherExamResponse,
    summary="Publish an exam (freezes its questions)",
)
def publish_exam(exam_id: int, current_user: TeacherUser, db: DbSession):
    return _exam_response(ExamService(db).publish(exam_id, current_user))


# ------------------------------------------------------------------ questions


@router.get(
    "/{exam_id}/questions",
    response_model=list[ExamQuestionResponse],
    summary="Questions in one of my exams",
)
def list_questions(exam_id: int, current_user: TeacherUser, db: DbSession):
    links = ExamService(db).list_questions(exam_id, current_user)
    return [_question_response(link) for link in links]


@router.post(
    "/{exam_id}/questions",
    response_model=ExamQuestionResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Add a question to a draft exam",
)
def add_question(
    exam_id: int, payload: QuestionCreate, current_user: TeacherUser, db: DbSession
):
    return _question_response(ExamService(db).add_question(exam_id, payload, current_user))


# Declared before /questions/{exam_question_id} so "order" is not parsed as an id.
@router.put(
    "/{exam_id}/questions/order",
    response_model=list[ExamQuestionResponse],
    summary="Reorder the questions in a draft exam",
)
def reorder_questions(
    exam_id: int,
    current_user: TeacherUser,
    db: DbSession,
    question_ids: Annotated[list[int], Body(embed=True)],
):
    links = ExamService(db).reorder_questions(exam_id, question_ids, current_user)
    return [_question_response(link) for link in links]


@router.put(
    "/{exam_id}/questions/{exam_question_id}",
    response_model=ExamQuestionResponse,
    summary="Edit a question in a draft exam",
)
def update_question(
    exam_id: int,
    exam_question_id: int,
    payload: QuestionCreate,
    current_user: TeacherUser,
    db: DbSession,
):
    return _question_response(
        ExamService(db).update_question(exam_id, exam_question_id, payload, current_user)
    )


@router.delete(
    "/{exam_id}/questions/{exam_question_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Remove a question from a draft exam",
)
def remove_question(
    exam_id: int, exam_question_id: int, current_user: TeacherUser, db: DbSession
) -> Response:
    ExamService(db).remove_question(exam_id, exam_question_id, current_user)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# --------------------------------------------------------------- join requests


@router.post(
    "/{exam_id}/join-request",
    response_model=JoinRequestResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Ask to sit this exam (student)",
)
def request_to_join(exam_id: int, current_user: StudentUser, db: DbSession):
    request = JoinRequestService(db).request_to_join(exam_id, current_user)
    return _join_request_response(request)


@router.get(
    "/{exam_id}/join-requests",
    response_model=list[JoinRequestResponse],
    summary="Requests to sit this exam (exam owner)",
)
def list_join_requests(
    exam_id: int,
    current_user: TeacherUser,
    db: DbSession,
    request_status: Annotated[
        str | None, Query(alias="status", description="pending, approved, rejected")
    ] = None,
):
    requests = JoinRequestService(db).list_for_exam(
        exam_id, current_user, status=request_status
    )
    return [_join_request_response(request) for request in requests]


@router.get(
    "/{exam_id}/security-summary",
    response_model=ExamSecuritySummary,
    summary="What every student's device reported during this exam (exam owner)",
)
def read_security_summary(exam_id: int, current_user: TeacherUser, db: DbSession):
    """A record, not a verdict (§38).

    Several of these have innocent explanations -- a call arrives, the network drops,
    a parent walks in -- so the platform counts and presents, and a human decides.
    """
    return SecurityService(db).summary_for_exam(exam_id, current_user)


@router.post(
    "/{exam_id}/join-requests/approve-all",
    response_model=BulkReviewResponse,
    summary="Approve pending requests in one transaction (exam owner)",
)
def approve_all(
    exam_id: int,
    current_user: TeacherUser,
    db: DbSession,
    payload: BulkReviewRequest | None = None,
):
    updated = JoinRequestService(db).review_all(
        exam_id,
        current_user,
        approve=True,
        request_ids=payload.request_ids if payload else None,
    )
    return BulkReviewResponse(updated=updated, status="approved")


@router.post(
    "/{exam_id}/join-requests/reject-all",
    response_model=BulkReviewResponse,
    summary="Reject pending requests in one transaction (exam owner)",
)
def reject_all(
    exam_id: int,
    current_user: TeacherUser,
    db: DbSession,
    payload: BulkReviewRequest | None = None,
):
    updated = JoinRequestService(db).review_all(
        exam_id,
        current_user,
        approve=False,
        request_ids=payload.request_ids if payload else None,
    )
    return BulkReviewResponse(updated=updated, status="rejected")


# ------------------------------------------------------------ attempts & results


@router.post(
    "/{exam_id}/start",
    response_model=AttemptResponse,
    summary="Start (or resume) this exam (student)",
)
def start_exam(exam_id: int, current_user: StudentUser, db: DbSession):
    """Runs every condition in §32 server-side. Calling it again while an attempt is
    running resumes that attempt rather than creating a second one."""
    service = AttemptService(db)
    attempt = service.start(exam_id, current_user)
    return service.build_view(attempt)


@router.get(
    "/{exam_id}/results",
    response_model=list[TeacherResultResponse],
    summary="Results for this exam (exam owner)",
)
def list_exam_results(exam_id: int, current_user: TeacherUser, db: DbSession):
    return ResultService(db).list_for_exam(exam_id, current_user)


@router.post(
    "/{exam_id}/results/publish",
    response_model=PublishResultsResponse,
    summary="Release the results to students (exam owner)",
)
def publish_exam_results(exam_id: int, current_user: TeacherUser, db: DbSession):
    published = ResultService(db).publish_for_exam(exam_id, current_user)
    return PublishResultsResponse(published=published)


@router.get(
    "/{exam_id}/grading",
    response_model=list[GradingQueueEntry],
    summary="Submissions and how much marking each still needs (exam owner)",
)
def grading_queue(exam_id: int, current_user: TeacherUser, db: DbSession):
    return GradingService(db).queue_for_exam(exam_id, current_user)


@router.get(
    "/{exam_id}/analytics",
    response_model=ExamAnalytics,
    summary="How this exam and its questions performed (exam owner)",
)
def exam_analytics(
    exam_id: int,
    current_user: TeacherUser,
    db: DbSession,
    pass_percentage: Annotated[
        float,
        Query(
            ge=0,
            le=100,
            description="Threshold to compute pass/fail against. The platform does not "
            "know a university's pass mark, so it is supplied here and echoed back.",
        ),
    ] = 40.0,
):
    return AnalyticsService(db).for_exam(
        exam_id, current_user, pass_percentage=pass_percentage
    )


@router.post(
    "/{exam_id}/questions/from-bank",
    response_model=list[ExamQuestionResponse],
    status_code=status.HTTP_201_CREATED,
    summary="Add existing questions from my library to a draft exam",
)
def add_questions_from_bank(
    exam_id: int,
    payload: AttachFromBankRequest,
    current_user: TeacherUser,
    db: DbSession,
):
    links = QuestionBankService(db).attach_to_exam(
        exam_id, payload.question_ids, current_user
    )
    return [_question_response(link) for link in links]
