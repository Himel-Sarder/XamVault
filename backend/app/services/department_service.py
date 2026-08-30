from __future__ import annotations

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.exceptions import ConflictError, NotFoundError
from app.models.course import Course
from app.models.department import Department
from app.models.enums import UserRole
from app.models.user import User
from app.repositories.department_repository import DepartmentRepository
from app.schemas.department import (
    DepartmentCreate,
    DepartmentDeletionImpact,
    DepartmentUpdate,
)


class DepartmentService:
    def __init__(self, db: Session) -> None:
        self.db = db
        self.departments = DepartmentRepository(db)

    def list_departments(self, *, include_inactive: bool = False) -> list[Department]:
        return self.departments.list_all(include_inactive=include_inactive)

    def get(self, department_id: int) -> Department:
        department = self.departments.get(department_id)
        if department is None:
            raise NotFoundError("Department not found")
        return department

    def create(self, data: DepartmentCreate) -> Department:
        code = data.code.strip().upper()
        if self.departments.get_by_code(code):
            raise ConflictError(f"Department code '{code}' already exists")
        department = self.departments.add(Department(code=code, name=data.name))
        self.db.commit()
        return department

    def update(self, department_id: int, data: DepartmentUpdate) -> Department:
        department = self.get(department_id)
        for field, value in data.model_dump(exclude_unset=True).items():
            setattr(department, field, value)
        self.db.commit()
        return department

    # ---------------------------------------------------------------- removal

    def deletion_impact(self, department_id: int) -> DepartmentDeletionImpact:
        """Who would be left without a department. Read before the confirmation."""
        department = self.get(department_id)

        def count(model, column) -> int:
            return int(
                self.db.execute(
                    select(func.count()).select_from(model).where(column == department.id)
                ).scalar_one()
            )

        return DepartmentDeletionImpact(
            courses=count(Course, Course.department_id),
            teachers=int(
                self.db.execute(
                    select(func.count())
                    .select_from(User)
                    .where(
                        User.department_id == department.id,
                        User.role == UserRole.TEACHER,
                    )
                ).scalar_one()
            ),
            students=int(
                self.db.execute(
                    select(func.count())
                    .select_from(User)
                    .where(
                        User.department_id == department.id,
                        User.role == UserRole.STUDENT,
                    )
                ).scalar_one()
            ),
        )

    def delete(self, department_id: int) -> None:
        """Removes a department.

        Nothing goes with it. Every foreign key pointing here is SET NULL, so the
        courses and people that belonged to it survive as unassigned -- which is a
        state the rest of the app already handles, because a department was always
        optional on both.
        """
        department = self.get(department_id)
        self.db.delete(department)
        self.db.commit()
