from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field

from app.schemas.common import ORMModel


class DepartmentCreate(BaseModel):
    code: str = Field(min_length=1, max_length=20)
    name: str = Field(min_length=1, max_length=150)


class DepartmentUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=150)
    is_active: bool | None = None


class DepartmentResponse(ORMModel):
    id: int
    code: str
    name: str
    is_active: bool
    created_at: datetime


class DepartmentDeletionImpact(BaseModel):
    """What loses its department if this one goes.

    Nothing is destroyed: every reference to a department is ON DELETE SET NULL, so a
    course or a person simply becomes unassigned. Worth saying out loud before the fact,
    because "unassigned" is still a change somebody has to put right.
    """

    courses: int
    teachers: int
    students: int

    @property
    def is_empty(self) -> bool:
        return not (self.courses or self.teachers or self.students)
