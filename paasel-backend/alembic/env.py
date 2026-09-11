"""Alembic env — reads DATABASE_URL from app config, migrates synchronously.

Migrations run over psycopg2 rather than the app's asyncpg driver, on purpose.
asyncpg sends every statement through the extended query protocol, which cannot
accept more than one command per execute — so any `op.execute` holding a
multi-statement DDL block fails with "cannot insert multiple commands into a
prepared statement". Several migrations here are written that way, and they read
far better as one block per concern than as dozens of one-line executes.

Alembic gains nothing from being async: it runs once, serially, at deploy time.
So the driver is swapped here and only here. The app's DATABASE_URL stays
asyncpg, which its config validator still enforces.
"""

from logging.config import fileConfig

from alembic import context
from sqlalchemy import create_engine, pool

from app.core.config import settings
from app.core.database import Base
from app.models import entities  # noqa: F401 — register all models

config = context.config

if config.config_file_name:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def sync_database_url() -> str:
    """The app's async URL rewritten onto a synchronous driver."""
    return settings.database_url.replace(
        "postgresql+asyncpg://", "postgresql+psycopg2://", 1
    )


config.set_main_option("sqlalchemy.url", sync_database_url())


def run_migrations_offline() -> None:
    context.configure(
        url=sync_database_url(),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = create_engine(sync_database_url(), poolclass=pool.NullPool)
    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()
    connectable.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
