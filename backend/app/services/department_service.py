from __future__ import annotations

from sqlalchemy.orm import Session

from app.core.exceptions import ConflictError, NotFoundError
from app.models.department import Department
from app.repositories.department_repository import DepartmentRepository
from app.schemas.department import DepartmentCreate, DepartmentUpdate


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
