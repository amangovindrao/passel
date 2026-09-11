"""Report what is actually in the dev and test databases.

Written after a Docker engine restart left one of them reachable but empty —
"the port answers" and "the schema is there" are different questions, and
guessing between them wastes more time than checking.

    python scripts/db_state.py
"""

from __future__ import annotations

import asyncio

from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

TARGETS = [
    ("dev  (5434)", "postgresql+asyncpg://paasel:paasel@localhost:5434/paasel"),
    (
        "test (5433)",
        "postgresql+asyncpg://paasel:paasel@localhost:5433/paasel_test",
    ),
]

COUNTS = ("users", "shops", "products", "orders", "delivery_partner_profiles")


async def report(label: str, url: str) -> None:
    engine = create_async_engine(url, connect_args={"timeout": 8})
    try:
        async with engine.connect() as conn:
            tables = await conn.scalar(
                text(
                    "SELECT count(*) FROM information_schema.tables "
                    "WHERE table_schema = 'public'"
                )
            )
            version = await conn.scalar(
                text("SELECT version_num FROM alembic_version")
            ) if tables else None
            print(f"{label}: {tables} public tables, alembic={version}")

            if not tables:
                print("    empty — run alembic upgrade head against this one")
                return

            for name in COUNTS:
                try:
                    n = await conn.scalar(text(f"SELECT count(*) FROM {name}"))
                    print(f"    {name:28s} {n}")
                except Exception:  # noqa: BLE001 — table simply absent
                    print(f"    {name:28s} (missing)")
    except Exception as exc:  # noqa: BLE001
        print(f"{label}: UNREACHABLE {type(exc).__name__}: {exc}")
    finally:
        await engine.dispose()


async def main() -> None:
    for label, url in TARGETS:
        await report(label, url)
        print()


if __name__ == "__main__":
    asyncio.run(main())
