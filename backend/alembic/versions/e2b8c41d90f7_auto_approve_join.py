"""auto approve join

Whether an enrolled student may sit an exam without being admitted by hand.

Defaults to false, so every exam that already exists keeps the behaviour its teacher
set it up with. Turning the approval step off has to be a deliberate act, not something
a migration does on everyone's behalf.

Revision ID: e2b8c41d90f7
Revises: a3f1e70b52d4
Create Date: 2026-08-30 16:10:00.000000
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "e2b8c41d90f7"
down_revision: str | None = "a3f1e70b52d4"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("exam_settings") as batch:
        batch.add_column(
            sa.Column(
                "auto_approve_join",
                sa.Boolean(),
                nullable=False,
                server_default=sa.false(),
            )
        )


def downgrade() -> None:
    with op.batch_alter_table("exam_settings") as batch:
        batch.drop_column("auto_approve_join")
