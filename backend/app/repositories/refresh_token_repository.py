from __future__ import annotations

from datetime import datetime

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.models.refresh_token import RefreshToken


class RefreshTokenRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def get_by_jti(self, jti: str) -> RefreshToken | None:
        return self.db.execute(
            select(RefreshToken).where(RefreshToken.jti == jti)
        ).scalar_one_or_none()

    def add(self, token: RefreshToken) -> RefreshToken:
        self.db.add(token)
        self.db.flush()
        return token

    def revoke(self, token: RefreshToken, now: datetime) -> None:
        token.revoked_at = now
        self.db.flush()

    def revoke_all_for_user(self, user_id: int, now: datetime) -> int:
        """Used on password change and on refresh-token reuse (a theft signal)."""
        result = self.db.execute(
            update(RefreshToken)
            .where(RefreshToken.user_id == user_id, RefreshToken.revoked_at.is_(None))
            .values(revoked_at=now)
        )
        self.db.flush()
        return result.rowcount or 0

    def delete_expired(self, before: datetime) -> int:
        rows = self.db.execute(
            select(RefreshToken).where(RefreshToken.expires_at < before)
        ).scalars().all()
        for row in rows:
            self.db.delete(row)
        self.db.flush()
        return len(rows)
