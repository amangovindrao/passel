"""Route distance estimation.

This is the single seam where a real Directions API would be plugged in. Until
then it uses the same approximation the order-placement quote already relies on:
PostGIS great-circle distance inflated by a road-network factor. Keeping every
caller behind one function means swapping in Google Directions later is a
one-file change rather than a hunt through the codebase.
"""

from collections.abc import Sequence

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

# Straight-line to road-distance multiplier. Matches order_placement's quote so
# a batched fee and a solo fee are computed on the same basis.
ROUTE_FACTOR = 1.3


async def leg_distance_m(db: AsyncSession, origin: object, destination: object) -> float:
    """Estimated road distance in metres between two geography points."""
    # CAST(... AS geography) rather than the ::geography shorthand: SQLAlchemy
    # reads ':origin::geography' as two colon-prefixed parameters and hands
    # Postgres a syntax error.
    result = await db.scalar(
        text(
            "SELECT ST_Distance("
            "CAST(:origin AS geography), CAST(:destination AS geography))"
        ),
        {"origin": str(origin), "destination": str(destination)},
    )
    return float(result or 0) * ROUTE_FACTOR


async def route_distance_m(db: AsyncSession, waypoints: Sequence[object]) -> float:
    """Estimated road distance for a multi-stop route, visited in order.

    Fewer than two waypoints is a zero-length route rather than an error, so
    callers comparing two candidate routes don't need to special-case it.
    """
    if len(waypoints) < 2:
        return 0.0

    total = 0.0
    for origin, destination in zip(waypoints, waypoints[1:], strict=False):
        total += await leg_distance_m(db, origin, destination)
    return total
