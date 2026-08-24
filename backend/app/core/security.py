"""Password hashing and JWT issuing/decoding.

Nothing here touches the database or FastAPI; it is pure crypto plumbing so it can be
unit-tested on its own.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any, Final, Literal

import jwt
from pwdlib import PasswordHash
from pwdlib.hashers.argon2 import Argon2Hasher
from pwdlib.hashers.bcrypt import BcryptHasher

from app.core.config import settings

TokenType = Literal["access", "refresh"]

ACCESS: Final[TokenType] = "access"
REFRESH: Final[TokenType] = "refresh"

# Argon2id issues new hashes; bcrypt stays in the chain so hashes imported from another
# system still verify and get upgraded on the user's next successful login.
_password_hash = PasswordHash((Argon2Hasher(), BcryptHasher()))

# Verified against when the user does not exist, so "unknown id" and "wrong password"
# take comparable time and the endpoint is not a user-id oracle.
_DUMMY_HASH = _password_hash.hash("uniexam-dummy-password-for-timing-equalisation")


class TokenError(Exception):
    """Raised when a token is absent, malformed, expired or of the wrong type."""


@dataclass(frozen=True, slots=True)
class TokenPayload:
    subject: int
    token_type: TokenType
    jti: str
    expires_at: datetime
    role: str | None = None


@dataclass(frozen=True, slots=True)
class IssuedToken:
    token: str
    jti: str
    expires_at: datetime


# --------------------------------------------------------------------------- passwords


def hash_password(password: str) -> str:
    return _password_hash.hash(password)


def verify_password(password: str, password_hash: str | None) -> tuple[bool, str | None]:
    """Return ``(is_valid, upgraded_hash_or_None)``.

    ``password_hash`` may be ``None`` for a user that does not exist; a dummy verification
    still runs so the caller's timing does not reveal that.
    """
    if not password_hash:
        _password_hash.verify(password, _DUMMY_HASH)
        return False, None
    try:
        return _password_hash.verify_and_update(password, password_hash)
    except Exception:
        # Unrecognisable stored hash: treat as a failed login, never as a crash.
        return False, None


# ------------------------------------------------------------------------------ tokens


def _create_token(
    subject: int,
    token_type: TokenType,
    expires_delta: timedelta,
    extra_claims: dict[str, Any] | None = None,
) -> IssuedToken:
    now = datetime.now(UTC)
    expires_at = now + expires_delta
    jti = uuid.uuid4().hex
    claims: dict[str, Any] = {
        "sub": str(subject),  # PyJWT requires `sub` to be a string
        "type": token_type,
        "jti": jti,
        "iat": int(now.timestamp()),
        "exp": int(expires_at.timestamp()),
    }
    if extra_claims:
        claims.update(extra_claims)
    token = jwt.encode(claims, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)
    return IssuedToken(token=token, jti=jti, expires_at=expires_at)


def create_access_token(subject: int, role: str) -> IssuedToken:
    return _create_token(
        subject,
        ACCESS,
        timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES),
        {"role": role},
    )


def create_refresh_token(subject: int) -> IssuedToken:
    return _create_token(
        subject, REFRESH, timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    )


def decode_token(token: str, expected_type: TokenType) -> TokenPayload:
    """Decode and validate a token, or raise :class:`TokenError`.

    The ``type`` claim is checked here rather than at the call site: without it a
    long-lived refresh token would work as a bearer credential, and an access token
    could be replayed at ``/auth/refresh``.
    """
    try:
        claims = jwt.decode(
            token,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM],
            options={"require": ["exp", "iat", "sub", "jti"]},
        )
    except jwt.ExpiredSignatureError as exc:
        raise TokenError("Token has expired") from exc
    except jwt.PyJWTError as exc:
        raise TokenError("Token is invalid") from exc

    if claims.get("type") != expected_type:
        raise TokenError(f"Expected a {expected_type} token")

    try:
        subject = int(claims["sub"])
    except (KeyError, TypeError, ValueError) as exc:
        raise TokenError("Token subject is invalid") from exc

    return TokenPayload(
        subject=subject,
        token_type=expected_type,
        jti=str(claims["jti"]),
        expires_at=datetime.fromtimestamp(claims["exp"], tz=UTC),
        role=claims.get("role"),
    )
