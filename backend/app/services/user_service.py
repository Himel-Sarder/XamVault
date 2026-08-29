"""User administration (admin-only operations) and self-service profile reads."""

from __future__ import annotations

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.exceptions import ConflictError, InvalidRequestError, NotFoundError
from app.core.security import hash_password
from app.models.attempt import ExamAttempt
from app.models.course import Course, CourseEnrollment
from app.models.enums import UserRole
from app.models.exam import Exam, ExamQuestion
from app.models.question import Question
from app.models.result import Result
from app.models.user import StudentProfile, TeacherProfile, User
from app.repositories.department_repository import DepartmentRepository
from app.repositories.user_repository import UserRepository
from app.schemas.user import UserCreate, UserUpdate


class UserService:
    def __init__(self, db: Session) -> None:
        self.db = db
        self.users = UserRepository(db)
        self.departments = DepartmentRepository(db)

    # ----------------------------------------------------------------- reads

    def get_detail(self, user_id: int) -> User:
        user = self.users.get_with_profiles(user_id)
        if user is None:
            raise NotFoundError("User not found")
        return user

    def list_users(
        self, *, role: str | None, search: str | None, offset: int, limit: int
    ) -> tuple[list[User], int]:
        if role is not None and role not in tuple(UserRole):
            raise InvalidRequestError(f"Unknown role '{role}'")
        return self.users.list_paged(role=role, search=search, offset=offset, limit=limit)

    # ---------------------------------------------------------------- writes

    def create_user(self, data: UserCreate) -> User:
        if self.users.get_by_login_id(data.user_id):
            raise ConflictError(f"User ID '{data.user_id}' is already taken")
        if data.email and self.users.get_by_email(data.email):
            raise ConflictError(f"Email '{data.email}' is already registered")
        if data.department_id is not None and not self.departments.get(data.department_id):
            raise InvalidRequestError("department_id does not refer to a department")

        user = User(
            user_id=data.user_id,
            password_hash=hash_password(data.password),
            name=data.name,
            email=data.email,
            role=data.role,
            department_id=data.department_id,
            is_active=True,
        )
        self.users.add(user)

        if data.role == UserRole.STUDENT:
            if self.users.student_id_taken(data.student_id or ""):
                raise ConflictError(f"Student ID '{data.student_id}' is already taken")
            self.users.add_student_profile(
                StudentProfile(
                    user_id=user.id,
                    student_id=data.student_id,
                    department_id=data.department_id,
                    study_year=data.study_year,
                semester=data.semester,
                    session=data.session,
                )
            )
        elif data.role == UserRole.TEACHER:
            if self.users.teacher_id_taken(data.teacher_id or ""):
                raise ConflictError(f"Teacher ID '{data.teacher_id}' is already taken")
            self.users.add_teacher_profile(
                TeacherProfile(
                    user_id=user.id,
                    teacher_id=data.teacher_id,
                    department_id=data.department_id,
                    designation=data.designation,
                )
            )

        self.db.commit()
        return self.get_detail(user.id)

    def update_user(self, user_id: int, data: UserUpdate) -> User:
        user = self.users.get(user_id)
        if user is None:
            raise NotFoundError("User not found")

        fields = data.model_dump(exclude_unset=True)
        if "email" in fields and fields["email"]:
            existing = self.users.get_by_email(fields["email"])
            if existing and existing.id != user.id:
                raise ConflictError(f"Email '{fields['email']}' is already registered")
        if fields.get("department_id") is not None and not self.departments.get(
            fields["department_id"]
        ):
            raise InvalidRequestError("department_id does not refer to a department")

        for field, value in fields.items():
            setattr(user, field, value)
        self.db.commit()
        return self.get_detail(user.id)

    # -------------------------------------------------------------- removal

    def _authored_exam_ids(self, user_id: int) -> list[int]:
        """Every exam that would go: written by them, or sitting on a course they run.

        Both, because a course cannot outlive its owner -- ``courses.created_by`` is
        NOT NULL -- so deleting the account takes the course, and the course takes the
        exams on it whoever wrote them.
        """
        return list(
            self.db.execute(
                select(Exam.id).where(
                    (Exam.teacher_id == user_id)
                    | Exam.course_id.in_(
                        select(Course.id).where(Course.created_by == user_id)
                    )
                )
            )
            .scalars()
            .all()
        )

    def deletion_impact(self, user_id: int) -> dict[str, int]:
        """What deleting this account would take with it.

        Read before the confirmation is shown, so an administrator is told what they
        are about to destroy rather than discovering it afterwards.

        The two halves matter to different people. What the account *authored* --
        courses, exams, questions -- is the person's own work. What those exams *hold*
        -- other students' attempts and results -- is not, and it goes too. The second
        number is the one worth reading twice.
        """
        user = self.users.get(user_id)
        if user is None:
            raise NotFoundError("User not found")

        def count(model, column) -> int:
            return int(
                self.db.execute(
                    select(func.count()).select_from(model).where(column == user.id)
                ).scalar_one()
            )

        exam_ids = self._authored_exam_ids(user.id)

        def on_those_exams(model, column) -> int:
            if not exam_ids:
                return 0
            return int(
                self.db.execute(
                    select(func.count()).select_from(model).where(column.in_(exam_ids))
                ).scalar_one()
            )

        return {
            # Authored: the account's own work, which goes with it.
            "courses": count(Course, Course.created_by),
            "exams": len(exam_ids),
            "questions": count(Question, Question.created_by),
            # Their own record, as somebody who sat exams.
            "attempts": count(ExamAttempt, ExamAttempt.student_id),
            "results": count(Result, Result.student_id),
            "enrolments": count(CourseEnrollment, CourseEnrollment.student_id),
            # Other people's work, destroyed as a consequence of the above.
            "student_attempts": on_those_exams(ExamAttempt, ExamAttempt.exam_id),
            "student_results": on_those_exams(Result, Result.exam_id),
        }

    def _delete_authored_content(self, user: User) -> None:
        """Removes the courses, exams and questions the account wrote.

        Order is the whole of it. Courses first, because the database cascades their
        exams away and that clears most of the links a question is held by. Then any
        exam the person wrote on somebody else's course. Only then the questions, which
        are what the remaining links point at.

        ``exam_questions.question_id`` is RESTRICT, so a question still on a surviving
        exam would refuse to go. That cannot happen through the API -- a question is
        created by the author of the exam it is added to, and never shared -- but the
        links are cleared explicitly rather than left to raise an integrity error that
        says nothing an administrator could act on.
        """
        for course in (
            self.db.execute(select(Course).where(Course.created_by == user.id))
            .scalars()
            .all()
        ):
            self.db.delete(course)
        self.db.flush()

        for exam in (
            self.db.execute(select(Exam).where(Exam.teacher_id == user.id))
            .scalars()
            .all()
        ):
            self.db.delete(exam)
        self.db.flush()

        question_ids = list(
            self.db.execute(select(Question.id).where(Question.created_by == user.id))
            .scalars()
            .all()
        )
        if question_ids:
            for link in (
                self.db.execute(
                    select(ExamQuestion).where(ExamQuestion.question_id.in_(question_ids))
                )
                .scalars()
                .all()
            ):
                self.db.delete(link)
            self.db.flush()

            for question in (
                self.db.execute(select(Question).where(Question.id.in_(question_ids)))
                .scalars()
                .all()
            ):
                self.db.delete(question)
            self.db.flush()

    def delete_user(self, user_id: int, actor: User) -> None:
        """Removes an account and everything that belongs to it.

        Two refusals remain.

        Deleting yourself is refused because an administrator who does it has no way
        back: there may be no other admin, and the account cannot restore itself.

        Deleting an *active* account is refused because deactivating is the reversible
        version of the same intent, and doing it first means nobody destroys a live
        account in one step. It is the same shape as cancelling an exam before deleting
        it.

        Authoring content is no longer a refusal. A teacher who has left takes their
        courses, exams and questions with them, which is what an administrator asking
        to delete a teacher is asking for. It does mean students' attempts and results
        on those exams go too -- they hang off the exam -- so ``deletion_impact``
        counts them separately and the confirmation says so before anything happens.
        """
        user = self.users.get(user_id)
        if user is None:
            raise NotFoundError("User not found")

        if user.id == actor.id:
            raise ConflictError(
                "You cannot delete your own account. Ask another administrator.",
                code="cannot_delete_self",
            )
        if user.is_active:
            raise ConflictError(
                "Deactivate this account first. That stops them signing in without "
                "destroying anything, and you can delete it afterwards.",
                code="deactivate_first",
            )

        self._delete_authored_content(user)
        self.db.delete(user)
        self.db.commit()
