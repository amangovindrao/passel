# Paasel Backend

Production FastAPI backend for Paasel — a hyperlocal delivery marketplace by theScaleOn.

## Architecture

```
app/
├── api/v1/          Thin routers: auth, shops, products, orders, delivery, payments, wallets, subscriptions, admin
├── core/            Config (pydantic-settings), security (Supabase JWT), errors, logging, rate limiting
├── db/              Session factory, Base
├── domain/          Enums (single source of truth for all domain values)
├── models/          SQLAlchemy ORM models (one file — will split per domain in Phase 3)
├── schemas/         Pydantic request/response schemas
├── services/        Business logic (Phase 3)
├── repositories/    DB query layer (Phase 3)
├── worker.py        Celery tasks
└── main.py          App factory
```

## Auth

Supabase handles phone-OTP signup/login for all three apps. This backend **verifies** the Supabase-issued JWT (HS256) on every request. The user's role is always fetched from the `users` table — never from JWT claims — to avoid stale-role bugs.

Role gates: `require_role(UserRole.CUSTOMER)`, `require_role(UserRole.SHOP_OWNER)`, etc. Every endpoint requires an explicit role check.

## Database

PostgreSQL 16 + PostGIS. All geographic columns use `geography(Point, 4326)` with GiST indexes for real distance queries. All monetary values are **integer paise** (never float). The schema includes 21 tables matching the Paasel Master Plan exactly.

## Quick Start

```powershell
# 1. Start Postgres + Redis
docker compose up -d db redis

# 2. Create venv and install
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -e ".[test]"

# 3. Configure
copy .env.example .env
# Edit .env with your Supabase project credentials

# 4. Run migrations
alembic upgrade head

# 5. Start server
uvicorn app.main:app --reload

# 6. Run tests
pytest
```

## Endpoints (Phase 2)

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| GET | `/health` | None | DB connectivity check |
| GET | `/api/v1/auth/me` | Any role | Returns authenticated user profile |
| GET | `/docs` | None | OpenAPI (disabled in prod) |

All domain routers expose hidden `/_role-check` endpoints (excluded from OpenAPI) to verify access control wiring.

## Docker Compose

`docker compose up` starts PostgreSQL+PostGIS, Redis, the API (with auto-migration), and a Celery worker.

## Configuration

All values via environment variables (pydantic-settings):

| Variable | Required | Notes |
|----------|----------|-------|
| `DATABASE_URL` | Yes | Must use `postgresql+asyncpg://` |
| `SUPABASE_URL` | Yes | Your Supabase project URL |
| `SUPABASE_JWT_SECRET` | Yes | From Supabase dashboard → Settings → API |
| `REDIS_URL` | Yes | Celery broker + backend |
| `RAZORPAY_KEY_ID` | Yes | Payment gateway credentials |
| `RAZORPAY_KEY_SECRET` | Yes | |
| `GOOGLE_MAPS_API_KEY` | Yes | Distance calculations |
| `SENTRY_DSN` | No | Error tracking (empty = disabled) |
| `ENVIRONMENT` | No | `dev` / `staging` / `prod` (default: dev) |

App crashes at startup if any required value is missing.

## Supabase Notes

- Use the **JWT Secret** from Settings → API (not the anon key)
- For connection pooling, use the **Transaction Pooler** URL from Supabase (port 6543), not the direct connection
- The `users` table in this backend is separate from Supabase's `auth.users` — sync via webhook or trigger
