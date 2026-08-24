from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.department import Department


class DepartmentRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def get(self, department_id: int) -> Department | None:
        return self.db.get(Department, department_id)

    def get_by_code(self, code: str) -> Department | None:
        return self.db.execute(
            select(Department).where(Department.code == code)
        ).scalar_one_or_none()

    def list_all(self, *, include_inactive: bool = False) -> list[Department]:
        stmt = select(Department).order_by(Department.code)
        if not include_inactive:
            stmt = stmt.where(Department.is_active.is_(True))
        return list(self.db.execute(stmt).scalars().all())

    def add(self, department: Department) -> Department:
        self.db.add(department)
        self.db.flush()
        return department
