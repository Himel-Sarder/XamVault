"""year and semester

A single "semester 1-12" becomes a year of the programme (1-4) and which half of it
(1-2), which is how the university actually describes where a student is.

Written by hand rather than left as generated. Autogenerate found one of the two columns
and none of the data: it compares check constraints by name rather than by text, so
narrowing semester from 1-12 to 1-2 looked like no change at all, and it has no way to
know that an existing ``semester = 6`` means the second half of year three rather than
a value to leave alone.

Revision ID: c94c19b24a99
Revises: d67746d8e373
Create Date: 2026-08-29 03:10:00.000000
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "c94c19b24a99"
down_revision: str | None = "d67746d8e373"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_TABLES = ("courses", "student_profiles")


def _add_year(table: str) -> None:
    with op.batch_alter_table(table) as batch:
        batch.add_column(sa.Column("study_year", sa.Integer(), nullable=True))


def _constrain(table: str) -> None:
    with op.batch_alter_table(table) as batch:
        # The bare name, not the generated one: the naming convention is applied by the
        # metadata, and passing the full name here would see it applied a second time.
        if table == "student_profiles":
            batch.drop_constraint("semester", type_="check")
        batch.create_check_constraint(
            "study_year", "study_year IS NULL OR (study_year >= 1 AND study_year <= 4)"
        )
        batch.create_check_constraint(
            "semester", "semester IS NULL OR (semester >= 1 AND semester <= 2)"
        )


def _relax(table: str) -> None:
    with op.batch_alter_table(table) as batch:
        batch.drop_constraint("study_year", type_="check")
        batch.drop_constraint("semester", type_="check")
        if table == "student_profiles":
            batch.create_check_constraint(
                "semester", "semester IS NULL OR (semester >= 1 AND semester <= 12)"
            )


def upgrade() -> None:
    for table in _TABLES:
        _add_year(table)

    # Split the old running count into a year and a half of it. A programme of four
    # years with two semesters each means 5 is the first half of year three and 6 the
    # second, which is what the existing rows mean.
    #
    # Anything past 8 is clamped to the final year rather than dropped: an out-of-range
    # value is somebody's record, and losing it silently to satisfy a new constraint
    # would be worse than pinning it somewhere defensible.
    for table in _TABLES:
        op.execute(
            sa.text(
                f"""
                UPDATE {table}
                   SET study_year = MIN((semester + 1) / 2, 4),
                       semester   = ((semester - 1) % 2) + 1
                 WHERE semester IS NOT NULL
                """
            )
        )

    for table in _TABLES:
        _constrain(table)


def downgrade() -> None:
    for table in _TABLES:
        _relax(table)

    # Fold the pair back into one running count, so the column means again what it did.
    for table in _TABLES:
        op.execute(
            sa.text(
                f"""
                UPDATE {table}
                   SET semester = (study_year - 1) * 2 + semester
                 WHERE study_year IS NOT NULL AND semester IS NOT NULL
                """
            )
        )

    for table in _TABLES:
        with op.batch_alter_table(table) as batch:
            batch.drop_column("study_year")
