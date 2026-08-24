"""Alembic environment.

The database URL comes from application settings (i.e. from the environment), not from
alembic.ini, so the same command works locally and against Render without editing files.
"""

from __future__ import annotations

from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool

from app.core.config import settings
from app.core.database import Base
from app.models.types import UTCDateTime

# Importing the models package registers every table on Base.metadata; without it,
# autogenerate would happily produce a migration that drops everything.
import app.models  # noqa: F401

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

config.set_main_option("sqlalchemy.url", settings.DATABASE_URL.replace("%", "%%"))

target_metadata = Base.metadata


def _is_sqlite(url: str) -> bool:
    return url.startswith("sqlite")


def render_item(type_, obj, autogen_context) -> str | bool:
    """Render UTCDateTime as plain ``sa.DateTime(timezone=True)``.

    The decorator only adds Python-side UTC coercion; its DDL is an ordinary
    TIMESTAMPTZ. Emitting the plain type keeps migrations from importing application
    code, so an old revision still runs after the model layer is refactored.
    """
    if type_ == "type" and isinstance(obj, UTCDateTime):
        return "sa.DateTime(timezone=True)"
    return False


def run_migrations_offline() -> None:
    context.configure(
        url=settings.DATABASE_URL,
        target_metadata=target_metadata,
        literal_binds=True,
        compare_type=True,
        render_item=render_item,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            compare_type=True,
            render_item=render_item,
            # SQLite cannot ALTER most things; batch mode rebuilds the table instead.
            render_as_batch=_is_sqlite(settings.DATABASE_URL),
        )
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
