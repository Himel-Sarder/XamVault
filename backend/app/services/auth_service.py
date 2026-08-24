"""Authentication: login, refresh rotation, logout, password change."""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy.orm import Session

from app.core import security
from app.core.config import settings
from app.core.exceptions import AuthenticationError
from app.models.refresh_token import RefreshToken
from app.models.user import User
from app.repositories.refresh_token_repository import RefreshTokenRepository
from app.repositories.user_repository import UserRepository
from app.schemas.auth import TokenResponse
from app.schemas.user import UserSummary

# One message for every login failure. Distinguishing "no such user" from "wrong password"
# turns the endpoint into a directory of valid user ids.
_INVALID_CREDENTIALS = "Incorrect user ID or password"


class AuthService:
    def __init__(self, db: Session) -> None:
        self.db = db
        self.users = UserRepository(db)
        self.tokens = RefreshTokenRepository(db)

    # ------------------------------------------------------------------ login

    def login(self, login_id: str, password: str) -> TokenResponse:
        user = self.users.get_by_login_id(login_id)
        # verify_password runs a dummy hash comparison when user is None, so a missing
        # account and a wrong password cost roughly the same time.
        is_valid, upgraded_hash = security.verify_password(
            password, user.password_hash if user else None
        )
        if user is None or not is_valid:
            raise AuthenticationError(_INVALID_CREDENTIALS)
        if not user.is_active:
            raise AuthenticationError("This account has been deactivated")

        if upgraded_hash:
            # Hash was made by an older/weaker scheme; upgrade it now that we hold the
            # plaintext legitimately.
            user.password_hash = upgraded_hash

        response = self._issue_tokens(user)
        self.db.commit()
        return response

    # ---------------------------------------------------------------- refresh

    def refresh(self, refresh_token: str) -> TokenResponse:
        try:
            payload = security.decode_token(refresh_token, security.REFRESH)
        except security.TokenError as exc:
            raise AuthenticationError(str(exc)) from exc

        now = datetime.now(UTC)
        stored = self.tokens.get_by_jti(payload.jti)
        if stored is None:
            raise AuthenticationError("Refresh token is not recognised")

        if stored.is_revoked:
            # A revoked jti presented again means the token was captured and replayed
            # (or the client kept an old copy). Either way the family is no longer
            # trustworthy: kill every session for this user.
            self.tokens.revoke_all_for_user(stored.user_id, now)
            self.db.commit()
            raise AuthenticationError("Refresh token has been revoked; please log in again")

        if not stored.is_usable(now):
            raise AuthenticationError("Refresh token has expired")

        user = self.users.get(stored.user_id)
        if user is None or not user.is_active:
            raise AuthenticationError("This account is no longer active")

        self.tokens.revoke(stored, now)  # rotation: one refresh token, one use
        response = self._issue_tokens(user)
        self.db.commit()
        return response

    # ----------------------------------------------------------------- logout

    def logout(self, refresh_token: str) -> None:
        """Best-effort revocation. An unusable token is not an error: the caller's intent
        (end this session) is satisfied either way, and reporting the difference would
        leak whether a token is valid."""
        try:
            payload = security.decode_token(refresh_token, security.REFRESH)
        except security.TokenError:
            return
        stored = self.tokens.get_by_jti(payload.jti)
        if stored and not stored.is_revoked:
            self.tokens.revoke(stored, datetime.now(UTC))
            self.db.commit()

    # -------------------------------------------------------- change password

    def change_password(self, user: User, current_password: str, new_password: str) -> None:
        is_valid, _ = security.verify_password(current_password, user.password_hash)
        if not is_valid:
            raise AuthenticationError("Current password is incorrect")
        user.password_hash = security.hash_password(new_password)
        # Every existing session is invalidated: a password change is how a user reacts
        # to a suspected compromise, so old refresh tokens must stop working.
        self.tokens.revoke_all_for_user(user.id, datetime.now(UTC))
        self.db.commit()

    # ---------------------------------------------------------------- helpers

    def _issue_tokens(self, user: User) -> TokenResponse:
        access = security.create_access_token(user.id, user.role)
        refresh = security.create_refresh_token(user.id)
        self.tokens.add(
            RefreshToken(jti=refresh.jti, user_id=user.id, expires_at=refresh.expires_at)
        )
        return TokenResponse(
            access_token=access.token,
            refresh_token=refresh.token,
            expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
            user=UserSummary.model_validate(user),
        )
