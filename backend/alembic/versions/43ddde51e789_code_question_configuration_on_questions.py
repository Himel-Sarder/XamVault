"""code question configuration on questions

Revision ID: 43ddde51e789
Revises: cf7f2cc05073
Create Date: 2026-08-24 13:37:42.297306
"""
from __future__ import annotations

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = '43ddde51e789'
down_revision: str | None = 'cf7f2cc05073'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # batch_alter_table rebuilds the table on SQLite, which cannot ALTER a constraint
    # into place; on PostgreSQL it passes straight through to plain ALTER statements.
    with op.batch_alter_table("questions", schema=None) as batch_op:
        batch_op.add_column(sa.Column("language", sa.String(length=30), nullable=True))
        batch_op.add_column(sa.Column("time_limit_seconds", sa.Integer(), nullable=True))
        batch_op.add_column(sa.Column("memory_limit_mb", sa.Integer(), nullable=True))
        batch_op.create_check_constraint(
            "time_limit_positive", "time_limit_seconds IS NULL OR time_limit_seconds > 0"
        )
        batch_op.create_check_constraint(
            "memory_limit_positive", "memory_limit_mb IS NULL OR memory_limit_mb > 0"
        )


def downgrade() -> None:
    with op.batch_alter_table("questions", schema=None) as batch_op:
        batch_op.drop_constraint("time_limit_positive", type_="check")
        batch_op.drop_constraint("memory_limit_positive", type_="check")
        batch_op.drop_column("memory_limit_mb")
        batch_op.drop_column("time_limit_seconds")
        batch_op.drop_column("language")
