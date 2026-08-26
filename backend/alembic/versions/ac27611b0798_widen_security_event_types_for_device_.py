"""widen security event types for device conditions

Adds DEVELOPER_MODE, USB_DEBUGGING, SPLIT_SCREEN, EXTERNAL_DISPLAY and OVERLAY_DETECTED.

Autogenerate produced an empty migration: Alembic does not diff CHECK constraints, so a
widened allow-list looks like no change at all. Written by hand, and in batch mode so it
runs on SQLite as well as PostgreSQL.

Revision ID: ac27611b0798
Revises: fda030dea0e3
Create Date: 2026-08-26 12:01:04.501211
"""
from __future__ import annotations

from collections.abc import Sequence

from alembic import op

revision: str = "ac27611b0798"
down_revision: str | None = "fda030dea0e3"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


_OLD = (
    "APP_BACKGROUND",
    "APP_FOREGROUND",
    "SCREENSHOT_ATTEMPT",
    "SCREEN_RECORDING",
    "EXTERNAL_ACTIVITY",
    "NETWORK_DISCONNECT",
    "NETWORK_RECONNECT",
    "DEVICE_TIME_CHANGE",
    "EXAM_RESTART",
    "LOCKDOWN_ENGAGED",
    "LOCKDOWN_UNAVAILABLE",
)

_NEW = _OLD + (
    "DEVELOPER_MODE",
    "USB_DEBUGGING",
    "SPLIT_SCREEN",
    "EXTERNAL_DISPLAY",
    "OVERLAY_DETECTED",
)


def _check(values: tuple[str, ...]) -> str:
    joined = ", ".join(f"'{value}'" for value in values)
    return f"event_type IN ({joined})"


def _swap(old: tuple[str, ...], new: tuple[str, ...]) -> None:
    # The bare name, not the generated one: the naming convention is applied by the
    # metadata, and passing the full name here would see it applied a second time.
    with op.batch_alter_table("security_events") as batch:
        batch.drop_constraint("event_type", type_="check")
        batch.create_check_constraint("event_type", _check(new))


def upgrade() -> None:
    _swap(_OLD, _NEW)


def downgrade() -> None:
    # Rows recorded under a newly allowed type would violate the narrower constraint, so
    # they are folded into the closest older meaning rather than deleted: an event trail
    # is evidence, and a downgrade is no reason to lose part of one.
    op.execute(
        "UPDATE security_events SET event_type = 'EXTERNAL_ACTIVITY' "
        "WHERE event_type IN "
        "('DEVELOPER_MODE', 'USB_DEBUGGING', 'SPLIT_SCREEN', "
        "'EXTERNAL_DISPLAY', 'OVERLAY_DETECTED')"
    )
    _swap(_NEW, _OLD)
