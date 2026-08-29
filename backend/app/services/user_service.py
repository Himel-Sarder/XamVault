"""User administration (admin-only operations) and self-service profile reads."""

from __future__ import annotations

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.exceptions import ConflictError, InvalidRequestError, NotFoundError
from app.core.security import hash_password
from app.models.attempt import ExamAttempt
from app.models.course import Course, CourseEnrollment
from app.models.enums import UserRole
from app.models.exam import Exam
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

    def deletion_impact(self, user_id: int) -> dict[str, int]:
        """What deleting this account would take with it.

        Read before the confirmation is shown, so an administrator is told what they
        are about to destroy rather than discovering it afterwards.
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

        return {
            # Blocking: these are RESTRICT at the database, because an exam other people
            # sat cannot be allowed to lose its author.
            "courses": count(Course, Course.created_by),
            "exams": count(Exam, Exam.teacher_id),
            "questions": count(Question, Question.created_by),
            # Cascading: these go with the account.
            "attempts": count(ExamAttempt, ExamAttempt.student_id),
            "results": count(Result, Result.student_id),
            "enrolments": count(CourseEnrollment, CourseEnrollment.student_id),
        }

    def delete_user(self, user_id: int, actor: User) -> None:
        """Removes an account and everything that cascades from it.

        Three refusals, each for a different reason.

        Deleting yourself is refused because an administrator who does it has no way
        back: there may be no other admin, and the account cannot restore itself.

        Deleting an *active* account is refused because deactivating is the reversible
        version of the same intent, and doing it first means nobody destroys a live
        account in one step. It is the same shape as cancelling an exam before deleting
        it.

        Deleting an account that authored courses, exams or questions is refused
        outright, and not by this method -- the database says RESTRICT, because an exam
        other students sat must not lose its author. Checking here turns that from an
        integrity error into a sentence an administrator can act on.

        What remains does cascade: the person's own attempts, answers, results,
        enrolments, notifications, sessions and uploads. That is the point of the
        feature, and the caller is told the numbers first.
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

        impact = self.deletion_impact(user.id)
        owned = {key: impact[key] for key in ("courses", "exams", "questions") if impact[key]}
        if owned:
            described = ", ".join(f"{value} {key}" for key, value in owned.items())
            raise ConflictError(
                f"This account authored {described}, which other people's exams and "
                "results depend on. Reassign or remove those first.",
                code="user_owns_content",
            )

        self.db.delete(user)
        self.db.commit()
