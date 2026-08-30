from __future__ import annotations

from fastapi import APIRouter, status

from app.core.deps import AdminUser, CurrentUser, DbSession
from app.schemas.department import (
    DepartmentCreate,
    DepartmentDeletionImpact,
    DepartmentResponse,
    DepartmentUpdate,
)
from app.services.department_service import DepartmentService

router = APIRouter(prefix="/departments", tags=["departments"])


@router.get("", response_model=list[DepartmentResponse], summary="List departments")
def list_departments(_: CurrentUser, db: DbSession) -> object:
    return DepartmentService(db).list_departments()


@router.post(
    "",
    response_model=DepartmentResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a department (admin)",
)
def create_department(payload: DepartmentCreate, _: AdminUser, db: DbSession) -> object:
    return DepartmentService(db).create(payload)


@router.get("/{department_id}", response_model=DepartmentResponse, summary="Read a department")
def read_department(department_id: int, _: CurrentUser, db: DbSession) -> object:
    return DepartmentService(db).get(department_id)


@router.patch(
    "/{department_id}",
    response_model=DepartmentResponse,
    summary="Update a department (admin)",
)
def update_department(
    department_id: int, payload: DepartmentUpdate, _: AdminUser, db: DbSession
) -> object:
    return DepartmentService(db).update(department_id, payload)


@router.get(
    "/{department_id}/deletion-impact",
    response_model=DepartmentDeletionImpact,
    summary="Who would lose their department (admin)",
)
def department_deletion_impact(department_id: int, _: AdminUser, db: DbSession) -> object:
    """Nothing is destroyed by the delete -- these are the rows that become unassigned."""
    return DepartmentService(db).deletion_impact(department_id)


@router.delete(
    "/{department_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a department (admin)",
)
def delete_department(department_id: int, _: AdminUser, db: DbSession) -> None:
    """The courses and people in it survive, without a department.

    Every foreign key pointing at a department is SET NULL, and it was always an
    optional field on both, so there is nothing here to strand.
    """
    DepartmentService(db).delete(department_id)
