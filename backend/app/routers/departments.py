from __future__ import annotations

from fastapi import APIRouter, status

from app.core.deps import AdminUser, CurrentUser, DbSession
from app.schemas.department import DepartmentCreate, DepartmentResponse, DepartmentUpdate
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
