"""photo answers

A question the student answers by photographing work done on paper.

Two changes: somewhere to keep the photographs, and room in the question-type check
constraint for the new type. Autogenerate found the column but not the constraint —
check constraints are compared by name rather than by text, so a widened one looks
unchanged to it. Left out, every attempt to save a PHOTO_ANSWER question would fail on
a constraint violation with nothing to explain it.

Revision ID: d67746d8e373
Revises: 5ad5814934dc
Create Date: 2026-08-29 02:01:13.230336
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy import Text
from sqlalchemy.dialects import postgresql

revision: str = "d67746d8e373"
down_revision: str | None = "5ad5814934dc"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


_OLD = (
    "TEXT_MCQ",
    "IMAGE_TEXT_OPTIONS",
    "IMAGE_IMAGE_OPTIONS",
    "SHORT_ANSWER",
    "CODE_ANSWER",
)

_NEW = _OLD + ("PHOTO_ANSWER",)


def _check(values: tuple[str, ...]) -> str:
    joined = ", ".join(f"'{value}'" for value in values)
    return f"type IN ({joined})"


def _swap(new: tuple[str, ...]) -> None:
    # The bare name, not the generated one: the naming convention is applied by the
    # metadata, and passing the full name here would see it applied a second time.
    with op.batch_alter_table("questions") as batch:
        batch.drop_constraint("type", type_="check")
        batch.create_check_constraint("type", _check(new))


def upgrade() -> None:
    with op.batch_alter_table("student_answers", schema=None) as batch_op:
        batch_op.add_column(
            sa.Column(
                "answer_image_urls",
                sa.JSON().with_variant(
                    postgresql.JSONB(astext_type=Text()), "postgresql"
                ),
                nullable=True,
            )
        )
    _swap(_NEW)


def downgrade() -> None:
    # Narrowing the constraint would fail while any PHOTO_ANSWER question exists, which
    # is the correct outcome: the type has to be removed deliberately, not dropped from
    # under the papers that use it.
    _swap(_OLD)
    with op.batch_alter_table("student_answers", schema=None) as batch_op:
        batch_op.drop_column("answer_image_urls")
