"""Domain errors.

Services raise these instead of ``HTTPException`` so the business layer stays independent
of FastAPI; ``app.main`` registers a single handler that maps them to responses.
"""

from __future__ import annotations

from fastapi import status


class AppError(Exception):
    status_code: int = status.HTTP_400_BAD_REQUEST
    code: str = "error"

    def __init__(self, message: str, *, code: str | None = None) -> None:
        super().__init__(message)
        self.message = message
        if code:
            self.code = code


class AuthenticationError(AppError):
    status_code = status.HTTP_401_UNAUTHORIZED
    code = "authentication_failed"


class PermissionDeniedError(AppError):
    status_code = status.HTTP_403_FORBIDDEN
    code = "permission_denied"


class NotFoundError(AppError):
    status_code = status.HTTP_404_NOT_FOUND
    code = "not_found"


class ConflictError(AppError):
    status_code = status.HTTP_409_CONFLICT
    code = "conflict"


class InvalidRequestError(AppError):
    status_code = status.HTTP_400_BAD_REQUEST
    code = "invalid_request"


class ValidationIssuesError(AppError):
    """Carries a list of per-field reasons, not just one message.

    Publishing an exam can fail several checks at once; a teacher should see all of them
    rather than fixing one, retrying, and discovering the next.
    """

    status_code = status.HTTP_422_UNPROCESSABLE_CONTENT
    code = "validation_failed"

    def __init__(
        self, message: str, issues: list[dict[str, str]], *, code: str | None = None
    ) -> None:
        super().__init__(message, code=code)
        self.issues = issues
