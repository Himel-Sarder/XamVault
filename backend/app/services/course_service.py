"""Courses and enrolment.

This module carries the object-level authorization for Phase 1. Holding a teacher role is
never enough — the row's ``created_by`` must match the caller.
"""

from __future__ import annotations

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.exceptions import (
    ConflictError,
    InvalidRequestError,
    NotFoundError,
    PermissionDeniedError,
)
from app.models.attempt import ExamAttempt
from app.models.course import Course, CourseEnrollment
from app.models.exam import Exam, ExamQuestion
from app.models.result import Result
from app.models.enums import UserRole
from app.models.user import User
from app.repositories.course_repository import CourseRepository
from app.repositories.department_repository import DepartmentRepository
from app.repositories.user_repository import UserRepository
from app.schemas.course import (
    BulkEnrollmentResponse,
    CourseCreate,
    CourseDeletionImpact,
    CourseUpdate,
    EnrollmentCreate,
    SkippedEnrolment,
    SkipReason,
)
from app.schemas.user import UserSummary


class CourseService:
    def __init__(self, db: Session) -> None:
        self.db = db
        self.courses = CourseRepository(db)
        self.users = UserRepository(db)
        self.departments = DepartmentRepository(db)

    # --------------------------------------------------------- authorization

    def _get_visible(self, course_id: int, actor: User) -> Course:
        """404 rather than 403 for an invisible course: telling a teacher that course 42
        exists but belongs to someone else is itself a disclosure."""
        course = self.courses.get(course_id)
        if course is None or not self.courses.is_visible_to(course_id, actor):
            raise NotFoundError("Course not found")
        return course

    def _get_manageable(self, course_id: int, actor: User) -> Course:
        course = self._get_visible(course_id, actor)
        if actor.is_admin or (actor.is_teacher and course.created_by == actor.id):
            return course
        raise PermissionDeniedError("You do not have permission to modify this course")

    def assert_can_manage(self, course_id: int, actor: User) -> Course:
        """Public form of the ownership rule, so other services reuse it rather than
        re-implementing "is this the teacher's course?" and drifting from it."""
        return self._get_manageable(course_id, actor)

    # ----------------------------------------------------------------- reads

    def list_for(
        self, actor: User, *, offset: int, limit: int, active_only: bool
    ) -> tuple[list[Course], int]:
        return self.courses.list_visible_paged(
            actor, offset=offset, limit=limit, active_only=active_only
        )

    def get_for(self, course_id: int, actor: User) -> Course:
        return self._get_visible(course_id, actor)

    # ---------------------------------------------------------------- writes

    def create(self, data: CourseCreate, actor: User) -> Course:
        if not (actor.is_teacher or actor.is_admin):
            raise PermissionDeniedError("Only teachers and admins can create courses")
        code = data.course_code.strip().upper()
        if self.courses.get_by_code_and_session(code, data.session):
            raise ConflictError(
                f"Course '{code}' already exists for session '{data.session}'"
            )
        if data.department_id is not None and not self.departments.get(data.department_id):
            raise InvalidRequestError("department_id does not refer to a department")

        course = self.courses.add(
            Course(
                course_code=code,
                course_name=data.course_name,
                department_id=data.department_id,
                study_year=data.study_year,
                semester=data.semester,
                session=data.session,
                created_by=actor.id,  # from the token, never from the request body
            )
        )
        self.db.commit()
        return course

    def update(self, course_id: int, data: CourseUpdate, actor: User) -> Course:
        course = self._get_manageable(course_id, actor)
        fields = data.model_dump(exclude_unset=True)
        if fields.get("department_id") is not None and not self.departments.get(
            fields["department_id"]
        ):
            raise InvalidRequestError("department_id does not refer to a department")
        for field, value in fields.items():
            setattr(course, field, value)
        self.db.commit()
        return course

    # ---------------------------------------------------------------- removal

    def deletion_impact(self, course_id: int, actor: User) -> CourseDeletionImpact:
        """What deleting this course would destroy.

        Counted rather than estimated, and read before the confirmation is shown. A
        course is the root of a fair amount: every exam written on it, every attempt at
        those exams and every result from them. Nobody should discover that afterwards.
        """
        course = self._get_manageable(course_id, actor)

        exam_ids = list(
            self.db.execute(select(Exam.id).where(Exam.course_id == course.id))
            .scalars()
            .all()
        )

        def count(model, column) -> int:
            if not exam_ids:
                return 0
            return int(
                self.db.execute(
                    select(func.count()).select_from(model).where(column.in_(exam_ids))
                ).scalar_one()
            )

        attempt_ids = (
            list(
                self.db.execute(
                    select(ExamAttempt.id).where(ExamAttempt.exam_id.in_(exam_ids))
                )
                .scalars()
                .all()
            )
            if exam_ids
            else []
        )

        return CourseDeletionImpact(
            exams=len(exam_ids),
            # The links, not the bank entries: a question written for this course still
            # belongs to whoever wrote it and stays in their bank, reusable elsewhere.
            questions_on_those_exams=count(ExamQuestion, ExamQuestion.exam_id),
            attempts=len(attempt_ids),
            results=count(Result, Result.exam_id),
            enrolments=int(
                self.db.execute(
                    select(func.count())
                    .select_from(CourseEnrollment)
                    .where(CourseEnrollment.course_id == course.id)
                ).scalar_one()
            ),
        )

    def delete(self, course_id: int, actor: User) -> None:
        """Removes a course and everything written on it.

        Whoever may manage the course may delete it -- the teacher who runs it, or an
        administrator. The cascade is the database's: exams go with the course, and
        attempts, answers, results, join requests and security events go with the exams.

        Questions are deliberately spared. They live in their author's bank rather than
        on the course, and deleting a course should not quietly empty the bank of
        everything that was ever set on it.
        """
        course = self._get_manageable(course_id, actor)
        self.db.delete(course)
        self.db.commit()

    def assign_teacher(
        self, course_id: int, teacher_user_id: str, actor: User
    ) -> tuple[Course, int]:
        """Hands a course to a teacher. Administrators only.

        Ownership of a course is what decides who may edit it, publish exams on it and
        manage its roll, so this is the act of putting someone in charge of running it.

        It deliberately does **not** move the exams already written on the course. An
        exam carries its own author, its results point at that person, and rewriting
        that because the course changed hands would misattribute somebody's work. The
        count of what stayed behind is returned rather than left to be discovered by the
        new teacher failing to open a paper they expected to inherit.
        """
        if not actor.is_admin:
            raise PermissionDeniedError("Only an administrator can assign a course")

        course = self.courses.get(course_id)
        if course is None:
            raise NotFoundError("Course not found")

        teacher = self.users.get_by_login_id(teacher_user_id)
        if teacher is None:
            raise NotFoundError(f"No user with ID '{teacher_user_id}'")
        if not (teacher.is_teacher or teacher.is_admin):
            raise InvalidRequestError(
                f"'{teacher.user_id}' is a {teacher.role}, and a course is run by a "
                "teacher",
                code="not_a_teacher",
            )
        if not teacher.is_active:
            raise InvalidRequestError(
                f"'{teacher.user_id}' is deactivated and cannot be given a course",
                code="user_deactivated",
            )
        if course.created_by == teacher.id:
            raise ConflictError(
                f"'{teacher.user_id}' already runs this course", code="already_assigned"
            )

        previous_id = course.created_by
        course.created_by = teacher.id
        self.db.commit()

        kept = int(
            self.db.execute(
                select(func.count())
                .select_from(Exam)
                .where(Exam.course_id == course.id, Exam.teacher_id == previous_id)
            ).scalar_one()
        )
        self.db.refresh(course, ["creator"])
        return course, kept

    # ------------------------------------------------------------ enrollments

    def list_enrollments(self, course_id: int, actor: User) -> list[CourseEnrollment]:
        self._get_manageable(course_id, actor)
        return self.courses.list_enrollments(course_id)

    def enroll(self, course_id: int, data: EnrollmentCreate, actor: User) -> CourseEnrollment:
        course = self._get_manageable(course_id, actor)
        student = self.users.get_by_login_id(data.student_user_id)
        if student is None:
            raise NotFoundError(f"No user with ID '{data.student_user_id}'")
        if student.role != UserRole.STUDENT:
            raise InvalidRequestError(f"User '{student.user_id}' is not a student")
        if not student.is_active:
            raise InvalidRequestError(f"User '{student.user_id}' is deactivated")
        if self.courses.get_enrollment(course.id, student.id):
            raise ConflictError(f"'{student.user_id}' is already enrolled in this course")

        enrollment = self.courses.add_enrollment(
            CourseEnrollment(course_id=course.id, student_id=student.id)
        )
        self.db.commit()
        # Re-read so the response carries the eagerly loaded student summary.
        self.db.refresh(enrollment, ["student"])
        return enrollment

    #: The most candidates one request will return. A cohort is a few hundred at most,
    #: and a teacher scrolling past this many has the wrong filter, not too small a page.
    CANDIDATE_LIMIT = 300

    def enrolment_candidates(
        self,
        course_id: int,
        actor: User,
        *,
        study_year: int | None,
        semester: int | None,
        search: str | None,
    ) -> tuple[list[User], bool]:
        """Students who could be enrolled on this course, filtered by where they are.

        Scoped to the course rather than exposing the user directory: a teacher gets
        the people they could put on their own roll, and nothing else. Already-enrolled
        students are left out, because the answer to "add them" is that they are here.

        Returns the candidates and whether the list was cut short.
        """
        course = self._get_manageable(course_id, actor)

        enrolled = {
            row.student_id
            for row in self.courses.list_enrollments(course.id)
        }
        found = self.users.students_at_stage(
            study_year=study_year,
            semester=semester,
            # A course belongs to a department, and its roll almost always comes from
            # that department. Passing it narrows the list without the teacher having
            # to say so; a course with no department is not narrowed at all.
            department_id=course.department_id,
            search=search.strip() if search else None,
            exclude_ids=enrolled,
            limit=self.CANDIDATE_LIMIT + 1,
        )
        truncated = len(found) > self.CANDIDATE_LIMIT
        return found[: self.CANDIDATE_LIMIT], truncated

    def enroll_bulk(
        self, course_id: int, student_user_ids: list[str], actor: User
    ) -> BulkEnrollmentResponse:
        """Enrol a whole roll list, reporting each id that produced no place.

        The batch commits once, so nothing is left half-written. What it does *not* do
        is abort: an unknown or duplicate id is an ordinary outcome for a pasted list,
        and refusing the other fifty-nine names over one typo would help nobody.
        """
        course = self._get_manageable(course_id, actor)

        # Preserve the order the teacher supplied while collapsing repeats, so the
        # report reads in the same order as the list they pasted.
        wanted = list(dict.fromkeys(uid.strip() for uid in student_user_ids if uid.strip()))

        found = self.users.get_many_by_login_id(wanted)
        candidates = [
            user
            for user in (found.get(uid) for uid in wanted)
            if user is not None and user.role == UserRole.STUDENT and user.is_active
        ]
        already = self.courses.enrolled_student_ids(
            course.id, [user.id for user in candidates]
        )

        enrolled: list[User] = []
        skipped: list[SkippedEnrolment] = []
        for user_id in wanted:
            user = found.get(user_id)
            if user is None:
                reason: SkipReason = "not_found"
            elif user.role != UserRole.STUDENT:
                reason = "not_a_student"
            elif not user.is_active:
                reason = "deactivated"
            elif user.id in already:
                reason = "already_enrolled"
            else:
                self.courses.add_enrollment(
                    CourseEnrollment(course_id=course.id, student_id=user.id)
                )
                enrolled.append(user)
                continue
            skipped.append(SkippedEnrolment(student_user_id=user_id, reason=reason))

        self.db.commit()
        return BulkEnrollmentResponse(
            enrolled=[UserSummary.model_validate(user) for user in enrolled],
            skipped=skipped,
        )

    def unenroll(self, course_id: int, student_id: int, actor: User) -> None:
        self._get_manageable(course_id, actor)
        enrollment = self.courses.get_enrollment(course_id, student_id)
        if enrollment is None:
            raise NotFoundError("That student is not enrolled in this course")
        self.courses.delete_enrollment(enrollment)
        self.db.commit()
