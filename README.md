# 📦 Paasel — Hyperlocal Quick-Commerce & Delivery Platform

> **Hyperlocal retail marketplace connecting neighborhood Kirana stores, customers, and local delivery partners.**
> Built with ❤️ by **theScaleOn**.

---

## 📱 Ecosystem Applications

Paasel is architected as a modern Flutter monorepo with three dedicated mobile applications, shared modular packages, and a high-performance Python FastAPI backend:

| App | Target Users | Key Capabilities |
|---|---|---|
| **Passel Customer App** (`apps/customer_app`) | Consumers & Shoppers | Hyperlocal shop discovery, Shop ID search (`PSL-XXXX`), 100m multi-shop bundling, Private Cart group ordering, 7-minute delivery verification & issue resolution, Add More to active orders, Monthly Ration subscriptions, and dual theme personalities (**Classic Sleek** & **Pinkie Cute**). |
| **Passel Shop App** (`apps/shop_app`) | Kirana & Local Merchants | Merchant onboarding, PostGIS map pin, catalog generator with FMCG templates, AI photo product digitizer, live order acceptance, packing photo verification, and settlement ledger. |
| **Passel Rider App** (`apps/delivery_app`) | Delivery Partners | Instant online/offline toggle, geofenced order dispatch offers, multi-stop batch routing, pickup code verification, live location broadcasting, and real-time earnings ledger. |

---

## 📦 Shared Monorepo Packages

* **`packages/core`**: Domain models, DTOs, Supabase & REST repositories, AI product detection abstractions, and business rule validators.
* **`packages/ui_kit`**: Canonical design tokens (`AppColors`, `AppTypography`, `AppSpacing`, `AppRadius`), responsive widgets, and brand components.
* **`packages/camera_kit`**: Hardware camera integration, compression pipeline, and photo verification widgets.

---

## ⚡ Backend Services (`paasel-backend`)

* **FastAPI (Python 3.12)**: Asynchronous REST and WebSocket endpoints for low-latency communication.
* **PostgreSQL 16 + PostGIS**: Geospatial spatial indexing for 1–10 km shop discovery, rider dispatch radiuses, and clustering.
* **Redis + Celery**: Asynchronous task workers, driver dispatch cascades, order expiry countdowns, and WebSocket pub/sub.
* **Supabase Authentication**: Unified phone OTP authentication with JWT role verification (`customer`, `shop_owner`, `delivery_partner`, `admin`).
* **Razorpay Route**: Split payment disbursement and merchant settlement engine.

---

## 🛡️ Reliability & Zero-Freeze Guarantees

1. **Anti-Freeze Splash Screen**:
   * Synchronous auth session checks are executed post-first-frame (`WidgetsBinding.instance.addPostFrameCallback`) across all three applications.
   * Hard **4-second network timeout guard** ensures the app never hangs indefinitely on the splash screen, gracefully falling back to `/phone` login.
   * Complete unhandled exception absorption with diagnostic logging.
2. **Unified Account Identity**:
   * Seamless transition between Customer and Delivery Partner roles using the same phone number under a single unified identity.
   * Delivery earnings credit directly into the unified customer wallet.
3. **Private Cart Mode**:
   * Group orders support private cart concealment where member selections remain hidden until locked by the group host.
4. **Delivery Verification & Guarantee**:
   * 7-minute post-delivery issue window with Expired Item Safety Guarantee and instant dispute reporting.

---

## 🧪 Testing & Verification

The Paasel platform maintains extensive test coverage across the entire stack:

```bash
# Customer App Tests (42 tests)
cd apps/customer_app && flutter test

# Shop App Tests (29 tests)
cd apps/shop_app && flutter test

# Delivery App Tests (62 tests)
cd apps/delivery_app && flutter test

# Core Package Tests (26 tests)
cd packages/core && flutter test

# Backend Pytest Suite (78 tests)
cd paasel-backend && pytest
```

**Total Automated Tests:** **237+ Passing Tests (Zero Regressions)**.

---

## 🚀 Getting Started

### Prerequisites
* Flutter SDK (3.27+)
* Android SDK (NDK `27.0.12077973`)
* Python 3.12+ & Poetry
* PostgreSQL 16 with PostGIS extension & Redis

### Quick Run
```bash
# Run customer app
flutter run -d chrome apps/customer_app/lib/main.dart

# Run backend
cd paasel-backend
poetry install
poetry run uvicorn app.main:app --reload --port 8000
```

---

## 📄 License
Private & Proprietary — theScaleOn.
