"""installation settings

A single row holding the things an administrator sets about this particular
installation. Only the university name so far, which until now came from the
environment and so could not be changed without a redeploy.

Revision ID: a3f1e70b52d4
Revises: c94c19b24a99
Create Date: 2026-08-30 09:40:00.000000
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "a3f1e70b52d4"
down_revision: str | None = "c94c19b24a99"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "app_settings",
        # Not autoincrementing, and pinned to 1 by the check below: a settings table
        # that can hold two rows eventually holds two, and then no caller agrees on
        # which one is the truth.
        sa.Column("id", sa.Integer(), autoincrement=False, nullable=False),
        sa.Column("university_name", sa.String(length=150), nullable=False),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column("updated_by", sa.Integer(), nullable=True),
        sa.CheckConstraint("id = 1", name=op.f("ck_app_settings_single_row")),
        sa.ForeignKeyConstraint(
            ["updated_by"],
            ["users.id"],
            name=op.f("fk_app_settings_updated_by_users"),
            # The institution keeps its name when the administrator who set it leaves.
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_app_settings")),
    )

    # Deliberately no seed row. The service creates it on first read from
    # UNIVERSITY_NAME, so an installation that never opens the settings screen behaves
    # exactly as it did before this migration ran.


def downgrade() -> None:
    op.drop_table("app_settings")
