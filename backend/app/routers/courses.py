from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response, status

from app.core.deps import AdminUser, CurrentUser, DbSession, TeacherUser
from app.schemas.common import Page, PageParams
from app.schemas.course import (
    BulkEnrollmentCreate,
    CourseAssign,
    CourseAssignResponse,
    BulkEnrollmentResponse,
    CourseCreate,
    CourseResponse,
    CourseUpdate,
    EnrollmentCreate,
    EnrollmentResponse,
)
from app.services.course_service import CourseService

router = APIRouter(prefix="/courses", tags=["courses"])


def _course_response(course) -> CourseResponse:
    """Adds the holder's name, which is not a column on the row."""
    response = CourseResponse.model_validate(course)
    creator = getattr(course, "creator", None)
    return response.model_copy(
        update={"teacher_name": creator.name if creator else None}
    )


@router.get("", response_model=Page[CourseResponse], summary="List courses visible to me")
def list_courses(
    current_user: CurrentUser,
    db: DbSession,
    page: Annotated[PageParams, Depends()],
    active_only: Annotated[bool, Query(description="Hide archived courses")] = False,
) -> Page[CourseResponse]:
    """Scope depends on the caller: a student sees courses they are enrolled in, a teacher
    sees courses they created, an admin sees all of them."""
    courses, total = CourseService(db).list_for(
        current_user, offset=page.offset, limit=page.page_size, active_only=active_only
    )
    return Page[CourseResponse](
        items=[_course_response(course) for course in courses],
        total=total,
        page=page.page,
        page_size=page.page_size,
    )


@router.post(
    "",
    response_model=CourseResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a course (teacher/admin)",
)
def create_course(payload: CourseCreate, current_user: TeacherUser, db: DbSession) -> object:
    return _course_response(CourseService(db).create(payload, current_user))


@router.post(
    "/{course_id}/assign",
    response_model=CourseAssignResponse,
    summary="Put a teacher in charge of a course (admin)",
)
def assign_course(
    course_id: int, payload: CourseAssign, current_user: AdminUser, db: DbSession
) -> CourseAssignResponse:
    """Ownership decides who may edit the course, publish exams on it and manage its
    roll. Exams already written on it keep their own author -- see the count returned."""
    course, kept = CourseService(db).assign_teacher(
        course_id, payload.teacher_user_id, current_user
    )
    return CourseAssignResponse(
        course=_course_response(course), exams_kept_by_previous_teacher=kept
    )


@router.get("/{course_id}", response_model=CourseResponse, summary="Read a course")
def read_course(course_id: int, current_user: CurrentUser, db: DbSession) -> object:
    return _course_response(CourseService(db).get_for(course_id, current_user))


@router.patch("/{course_id}", response_model=CourseResponse, summary="Update own course")
def update_course(
    course_id: int, payload: CourseUpdate, current_user: TeacherUser, db: DbSession
) -> object:
    return _course_response(CourseService(db).update(course_id, payload, current_user))


@router.get(
    "/{course_id}/enrollments",
    response_model=list[EnrollmentResponse],
    summary="List enrolled students (course owner)",
)
def list_enrollments(course_id: int, current_user: TeacherUser, db: DbSession) -> object:
    return CourseService(db).list_enrollments(course_id, current_user)


@router.post(
    "/{course_id}/enrollments",
    response_model=EnrollmentResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Enrol a student (course owner)",
)
def enroll_student(
    course_id: int, payload: EnrollmentCreate, current_user: TeacherUser, db: DbSession
) -> object:
    return CourseService(db).enroll(course_id, payload, current_user)


@router.post(
    "/{course_id}/enrollments/bulk",
    response_model=BulkEnrollmentResponse,
    summary="Enrol a roll list (course owner)",
)
def enroll_students_bulk(
    course_id: int,
    payload: BulkEnrollmentCreate,
    current_user: TeacherUser,
    db: DbSession,
) -> object:
    """200, not 201: a batch can legitimately create nothing at all -- every id already
    enrolled, say -- and the caller reads what happened from the body either way."""
    return CourseService(db).enroll_bulk(course_id, payload.student_user_ids, current_user)


@router.delete(
    "/{course_id}/enrollments/{student_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Remove a student from a course (course owner)",
)
def unenroll_student(
    course_id: int, student_id: int, current_user: TeacherUser, db: DbSession
) -> Response:
    CourseService(db).unenroll(course_id, student_id, current_user)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
