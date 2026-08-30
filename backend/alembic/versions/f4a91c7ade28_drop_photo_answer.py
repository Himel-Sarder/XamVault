"""drop photo answer

The photograph question type is withdrawn. It required leaving the app for the camera,
and a pinned exam cannot do that: every way round it -- releasing the pin, taking it
back, capturing in-app -- traded one problem for another. The paper is better without
it.

Existing questions are converted to SHORT_ANSWER rather than deleted. They are somebody's
work, the wording survives, and a teacher can edit or remove them deliberately. Nobody
had answered one with photographs when this ran, so no marks move.

Revision ID: f4a91c7ade28
Revises: e2b8c41d90f7
Create Date: 2026-08-30 19:30:00.000000
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

from app.models.types import JSONColumn

revision: str = "f4a91c7ade28"
down_revision: str | None = "e2b8c41d90f7"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_WITHOUT_PHOTO = (
    "TEXT_MCQ",
    "IMAGE_TEXT_OPTIONS",
    "IMAGE_IMAGE_OPTIONS",
    "SHORT_ANSWER",
    "CODE_ANSWER",
)
_WITH_PHOTO = (*_WITHOUT_PHOTO, "PHOTO_ANSWER")


def _check(values: tuple[str, ...]) -> str:
    listed = ", ".join(f"'{value}'" for value in values)
    return f"type IN ({listed})"


def upgrade() -> None:
    # The bank first, then the frozen snapshots on published exams -- which are JSON,
    # so the type is rewritten inside the document rather than in a column.
    op.execute(
        sa.text("UPDATE questions SET type = 'SHORT_ANSWER' WHERE type = 'PHOTO_ANSWER'")
    )
    # The snapshots are JSON, and the two databases disagree about how to edit JSON in
    # place: jsonb_set and ->> are PostgreSQL's, json_set is SQLite's, and this has to
    # run on both -- production on one, the test suite's schema on the other. So the
    # rewrite happens in Python, through a table definition whose column type already
    # knows how to serialise for whichever dialect is connected.
    snapshots = sa.table(
        "exam_questions",
        sa.column("id", sa.Integer),
        sa.column("question_snapshot", JSONColumn),
    )
    connection = op.get_bind()
    for row in connection.execute(
        sa.select(snapshots.c.id, snapshots.c.question_snapshot)
    ).mappings():
        snapshot = row["question_snapshot"]
        if not isinstance(snapshot, dict) or snapshot.get("type") != "PHOTO_ANSWER":
            continue
        connection.execute(
            snapshots.update()
            .where(snapshots.c.id == row["id"])
            .values(question_snapshot={**snapshot, "type": "SHORT_ANSWER"})
        )

    with op.batch_alter_table("questions") as batch:
        batch.drop_constraint("type", type_="check")
        batch.create_check_constraint("type", _check(_WITHOUT_PHOTO))


def downgrade() -> None:
    # Widening only. The converted questions stay short answers: which of them were
    # photograph questions is not recorded anywhere, and guessing would be worse than
    # leaving them as what they now are.
    with op.batch_alter_table("questions") as batch:
        batch.drop_constraint("type", type_="check")
        batch.create_check_constraint("type", _check(_WITH_PHOTO))
