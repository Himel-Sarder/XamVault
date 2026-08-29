from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator


class AppSettingUpdate(BaseModel):
    """What an administrator may change about this installation."""

    university_name: str = Field(min_length=2, max_length=150)

    @field_validator("university_name")
    @classmethod
    def _trim(cls, value: str) -> str:
        # Printed at the top of every report, so surrounding whitespace would show.
        trimmed = " ".join(value.split())
        if len(trimmed) < 2:
            raise ValueError("University name must be at least 2 characters")
        return trimmed


class AppSettingResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    university_name: str
    updated_at: datetime | None = None
