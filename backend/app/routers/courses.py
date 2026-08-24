from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response, status

from app.core.deps import CurrentUser, DbSession, TeacherUser
from app.schemas.common import Page, PageParams
from app.schemas.course import (
    CourseCreate,
    CourseResponse,
    CourseUpdate,
    EnrollmentCreate,
    EnrollmentResponse,
)
from app.services.course_service import CourseService

router = APIRouter(prefix="/courses", tags=["courses"])


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
        items=[CourseResponse.model_validate(course) for course in courses],
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
    return CourseService(db).create(payload, current_user)


@router.get("/{course_id}", response_model=CourseResponse, summary="Read a course")
def read_course(course_id: int, current_user: CurrentUser, db: DbSession) -> object:
    return CourseService(db).get_for(course_id, current_user)


@router.patch("/{course_id}", response_model=CourseResponse, summary="Update own course")
def update_course(
    course_id: int, payload: CourseUpdate, current_user: TeacherUser, db: DbSession
) -> object:
    return CourseService(db).update(course_id, payload, current_user)


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
