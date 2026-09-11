"""FastAPI application factory."""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import sentry_sdk
import structlog
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi.middleware import SlowAPIMiddleware

from app.api.v1 import (
    addresses,
    admin,
    auth,
    customers,
    delivery,
    delivery_partners,
    health,
    order_history,
    order_placement,
    orders,
    payments,
    products,
    shop_management,
    shops,
    subscriptions,
    wallets,
)
from app.core.config import settings
from app.core.database import engine
from app.core.errors import register_error_handlers
from app.core.logging import configure_logging
from app.core.rate_limit import limiter
import app.services.settlement_hook  # noqa: F401 — registers on_transition hook

configure_logging()
log = structlog.get_logger()

if settings.sentry_dsn:
    sentry_sdk.init(
        dsn=settings.sentry_dsn,
        environment=settings.environment,
        traces_sample_rate=0.1,
    )


@asynccontextmanager
async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
    log.info("application_started", environment=settings.environment)
    yield
    await engine.dispose()
    log.info("application_stopped")


def create_app() -> FastAPI:
    app = FastAPI(
        title="Paasel API",
        version="2.0.0",
        docs_url="/docs" if settings.docs_enabled else None,
        redoc_url="/redoc" if settings.docs_enabled else None,
        openapi_url="/openapi.json" if settings.docs_enabled else None,
        lifespan=lifespan,
    )

    # Rate limiting
    app.state.limiter = limiter
    app.add_middleware(SlowAPIMiddleware)

    # CORS
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Error handlers
    register_error_handlers(app)

    # Routers
    app.include_router(health.router)
    app.include_router(auth.router)
    app.include_router(customers.router)
    app.include_router(addresses.router)
    # Static owner routes such as /api/v1/shops/mine must be registered
    # before the customer-facing /api/v1/shops/{shop_id} route.
    app.include_router(shop_management.router)
    app.include_router(shops.router)
    app.include_router(products.router)
    app.include_router(orders.router)
    app.include_router(order_placement.router)
    app.include_router(order_history.router)
    app.include_router(delivery.router)
    app.include_router(delivery_partners.router)
    app.include_router(payments.router)
    app.include_router(wallets.router)
    app.include_router(subscriptions.router)
    app.include_router(admin.router)

    return app


app = create_app()
