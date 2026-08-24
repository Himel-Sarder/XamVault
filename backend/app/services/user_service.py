"""User administration (admin-only operations) and self-service profile reads."""

from __future__ import annotations

from sqlalchemy.orm import Session

from app.core.exceptions import ConflictError, InvalidRequestError, NotFoundError
from app.core.security import hash_password
from app.models.enums import UserRole
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
