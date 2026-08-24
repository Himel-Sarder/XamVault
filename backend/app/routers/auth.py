from __future__ import annotations

from fastapi import APIRouter, Request, Response, status

from app.core.config import settings
from app.core.deps import CurrentUser, DbSession
from app.core.rate_limit import limiter
from app.schemas.auth import (
    ChangePasswordRequest,
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    TokenResponse,
)
from app.schemas.user import UserDetailResponse
from app.services.auth_service import AuthService
from app.services.user_service import UserService

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", response_model=TokenResponse, summary="Exchange credentials for tokens")
@limiter.limit(settings.LOGIN_RATE_LIMIT)
def login(request: Request, payload: LoginRequest, db: DbSession) -> TokenResponse:
    return AuthService(db).login(payload.user_id, payload.password)


@router.post("/refresh", response_model=TokenResponse, summary="Rotate a refresh token")
@limiter.limit(settings.REFRESH_RATE_LIMIT)
def refresh(request: Request, payload: RefreshRequest, db: DbSession) -> TokenResponse:
    return AuthService(db).refresh(payload.refresh_token)


@router.post(
    "/logout",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Revoke a refresh token",
)
def logout(request: Request, payload: LogoutRequest, db: DbSession) -> Response:
    AuthService(db).logout(payload.refresh_token)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/me", response_model=UserDetailResponse, summary="The authenticated user")
def read_me(current_user: CurrentUser, db: DbSession) -> object:
    return UserService(db).get_detail(current_user.id)


@router.post(
    "/change-password",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Change own password (revokes all sessions)",
)
def change_password(
    payload: ChangePasswordRequest, current_user: CurrentUser, db: DbSession
) -> Response:
    AuthService(db).change_password(
        current_user, payload.current_password, payload.new_password
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)
