"""HTTP layer. Routers translate requests into service calls and schemas into responses."""

from fastapi import APIRouter

from app.core.config import settings
from app.routers import (
    attempts,
    grading,
    auth,
    courses,
    departments,
    exams,
    join_requests,
    notifications,
    question_bank,
    reports,
    results,
    security,
    uploads,
    users,
)

api_router = APIRouter(prefix=settings.API_V1_PREFIX)
api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(departments.router)
api_router.include_router(courses.router)
api_router.include_router(exams.router)
api_router.include_router(join_requests.router)
api_router.include_router(attempts.router)
api_router.include_router(grading.router)
api_router.include_router(security.router)
api_router.include_router(uploads.router)
api_router.include_router(question_bank.router)
api_router.include_router(notifications.router)
api_router.include_router(results.router)
api_router.include_router(reports.router)

__all__ = ["api_router"]
