"""FastAPI dependencies: database session, current user, role guards."""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core import security
from app.core.database import get_db
from app.models.enums import UserRole
from app.models.user import User
from app.repositories.user_repository import UserRepository

DbSession = Annotated[Session, Depends(get_db)]

# auto_error=False so a missing header produces our own 401 with a WWW-Authenticate
# challenge rather than FastAPI's bare 403.
bearer_scheme = HTTPBearer(auto_error=False, description="JWT access token")

_UNAUTHENTICATED = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="Not authenticated",
    headers={"WWW-Authenticate": "Bearer"},
)


def get_current_user(
    db: DbSession,
    credentials: Annotated[
        HTTPAuthorizationCredentials | None, Depends(bearer_scheme)
    ] = None,
) -> User:
    """Resolve the caller from the access token.

    The user row is re-read on every request rather than trusted from the token claims, so
    deactivating an account or changing a role takes effect immediately instead of at
    token expiry.
    """
    if credentials is None or not credentials.credentials:
        raise _UNAUTHENTICATED
    try:
        payload = security.decode_token(credentials.credentials, security.ACCESS)
    except security.TokenError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(exc),
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc

    user = UserRepository(db).get(payload.subject)
    if user is None or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Account is inactive or no longer exists",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]


def require_roles(*roles: UserRole):
    """Coarse role gate.

    This answers "is the caller a teacher?" only. "Is it *this* teacher's course?" is an
    object-level question and is answered in the service layer — both checks are required.
    """
    allowed = {role.value for role in roles}

    def _guard(current_user: CurrentUser) -> User:
        if current_user.role not in allowed:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Your role is not permitted to perform this action",
            )
        return current_user

    return _guard


AdminUser = Annotated[User, Depends(require_roles(UserRole.ADMIN))]
TeacherUser = Annotated[User, Depends(require_roles(UserRole.TEACHER, UserRole.ADMIN))]
StudentUser = Annotated[User, Depends(require_roles(UserRole.STUDENT))]
