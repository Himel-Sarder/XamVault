"""Application configuration.

Every setting is read from the environment (or a local ``.env``). Nothing in this file
contains a host, user, password or port: see docs/security.md §11.
"""

from __future__ import annotations

import functools
from pathlib import Path
from typing import Literal

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND_DIR = Path(__file__).resolve().parents[2]

# Value shipped in .env.example so a fresh clone runs; refused in production.
DEV_SECRET_PLACEHOLDER = "dev-only-insecure-secret-change-me-in-production"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=BACKEND_DIR / ".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # ---- Application ----
    PROJECT_NAME: str = "UniExam API"
    VERSION: str = "0.1.0"
    API_V1_PREFIX: str = "/api/v1"
    ENV: Literal["development", "test", "production"] = "development"

    # ---- Database ----
    DATABASE_URL: str = "sqlite+pysqlite:///./uniexam_dev.db"
    DB_POOL_SIZE: int = 5
    DB_MAX_OVERFLOW: int = 10
    DB_POOL_RECYCLE_SECONDS: int = 1800
    DB_ECHO: bool = False

    # ---- JWT ----
    JWT_SECRET_KEY: str = DEV_SECRET_PLACEHOLDER
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7

    # ---- CORS ----
    # Comma-separated. Kept as a string so pydantic-settings does not try to JSON-decode it.
    CORS_ORIGINS: str = ""

    # ---- Reporting ----
    # Printed at the head of every exported report. The platform has no way to know a
    # university's name, so it is configuration rather than a hardcoded string.
    UNIVERSITY_NAME: str = "University"

    # ---- Uploads ----
    UPLOAD_DIR: str = "uploads"
    MAX_UPLOAD_SIZE_MB: int = 10

    # ---- Rate limiting (slowapi syntax) ----
    RATE_LIMIT_ENABLED: bool = True
    LOGIN_RATE_LIMIT: str = "10/minute"
    REFRESH_RATE_LIMIT: str = "30/minute"
    DEFAULT_RATE_LIMIT: str = "300/minute"

    # ---- Bootstrap admin (used by `python -m app.utils.seed`) ----
    FIRST_ADMIN_USER_ID: str = "admin"
    FIRST_ADMIN_PASSWORD: str = Field(default="", repr=False)
    FIRST_ADMIN_NAME: str = "System Administrator"

    @field_validator("DATABASE_URL")
    @classmethod
    def _normalise_database_url(cls, value: str) -> str:
        """Render hands out ``postgres://``; SQLAlchemy 2.x needs an explicit driver."""
        if value.startswith("postgres://"):
            return "postgresql+psycopg://" + value[len("postgres://") :]
        if value.startswith("postgresql://"):
            return "postgresql+psycopg://" + value[len("postgresql://") :]
        return value

    @property
    def cors_origins(self) -> list[str]:
        return [origin.strip() for origin in self.CORS_ORIGINS.split(",") if origin.strip()]

    @property
    def is_production(self) -> bool:
        return self.ENV == "production"

    @property
    def upload_path(self) -> Path:
        path = Path(self.UPLOAD_DIR)
        return path if path.is_absolute() else BACKEND_DIR / path

    @property
    def max_upload_size_bytes(self) -> int:
        return self.MAX_UPLOAD_SIZE_MB * 1024 * 1024

    def validate_for_runtime(self) -> None:
        """Fail loudly rather than serve production traffic with a known signing key.

        ``CORS_ORIGINS`` is deliberately *not* required. Empty means no browser origin is
        allowed, which is the safe default — a native mobile client sends no ``Origin``
        header and needs none. Demanding a value here would block a legitimate
        mobile-only deployment for no security gain.
        """
        if not self.is_production:
            return
        problems: list[str] = []
        if self.JWT_SECRET_KEY in (DEV_SECRET_PLACEHOLDER, "", None):
            problems.append("JWT_SECRET_KEY must be set to a strong random value")
        if len(self.JWT_SECRET_KEY) < 32:
            problems.append("JWT_SECRET_KEY must be at least 32 characters")
        if self.DATABASE_URL.startswith("sqlite"):
            problems.append("DATABASE_URL must point at PostgreSQL")
        if problems:
            raise RuntimeError(
                "Refusing to start in production:\n  - " + "\n  - ".join(problems)
            )


@functools.lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
