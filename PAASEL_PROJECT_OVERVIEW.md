# 🚀 Paasel — Complete Project Overview, Architecture & Financial Model

> **Paasel** is a hyperlocal delivery marketplace application built by **theScaleOn**. It connects local neighborhood retail shops (kirana/grocery stores) with nearby regular customers and local delivery partners for fast, seamless, and trackable delivery.

---

## 📌 1. Project Overview (In Short Points)

* **Hyperlocal Focus**: Connects local retail shops with customers within a 4 km delivery radius using PostGIS geographic spatial indexing.
* **Triple-App Ecosystem**:
  1. **Customer App** (Flutter): Browse local catalog, place recurring ration/grocery orders, live track delivery, OTP verification.
  2. **Shop Owner App** (Flutter): Inventory/product management, order acceptance, packing photo verification, subscription status tracking.
  3. **Delivery Partner App** (Flutter): Order assignment notification (Fresh & Batch detour), parallel multi-order delivery routing, pickup/delivery OTP validation, wallet earnings.
* **Robust FastAPI Backend**: High-performance Python backend with PostgreSQL 16 + PostGIS, Redis + Celery task queue for automated driver assignment cascades.
* **Supabase Authentication**: Secure Phone OTP signup/login across all applications with JWT role-based access control (`customer`, `shop_owner`, `delivery_partner`, `admin`).
* **Financial & Wallet Engine**: Integer-paise precision ledger, Razorpay Route split payments, COD debit balance tracking, and automated merchant subscriptions (₹249/month).

---

## 🏗️ 2. System Architecture & Tech Stack

```mermaid
graph TD
    subgraph Clients["📱 Flutter Apps Monorepo (Melos)"]
        CA["Customer App"]
        SA["Shop Owner App"]
        DA["Delivery Partner App"]
    end

    subgraph Shared["📦 Shared Packages"]
        CORE["core package"]
        UI["ui_kit package"]
        CAM["camera_kit package"]
    end

    CA --> CORE
    SA --> CORE
    DA --> CORE
    CA --> UI
    SA --> UI
    DA --> UI
    SA --> CAM
    DA --> CAM

    subgraph Backend["⚡ FastAPI Production Backend"]
        API["FastAPI App (ASGI)"]
        AUTH["Supabase Auth JWT Validator"]
        GEO["PostGIS Spatial Query Engine"]
        WORKER["Celery Task Worker"]
    end

    CA -->|HTTP / REST| API
    SA -->|HTTP / REST| API
    DA -->|HTTP / REST| API

    subgraph Storage["🗄️ Database & Cache"]
        DB[("PostgreSQL 16 + PostGIS")]
        REDIS[("Redis Cache / Broker")]
    end

    API --> DB
    API --> REDIS
    WORKER --> REDIS
    WORKER --> DB
    AUTH --> API

    subgraph External["🌐 External Services"]
        SUPA["Supabase (Phone OTP Auth)"]
        RZP["Razorpay Route (Payments & Splits)"]
        MAPS["Google Maps API (Geo Distance)"]
    end

    API --> RZP
    API --> MAPS
    Clients --> SUPA
```

---

## 🔄 3. End-to-End Order & Delivery Lifecycle Flowchart

```mermaid
flowchart TD
    Start([Customer Opens App]) --> Browse[Browse Nearby Shops within 4km Radius]
    Browse --> Select[Select Grocery / Ration Items & Place Order]
    Select --> PayChoice{Payment Mode}
    PayChoice -->|Online| Razorpay[Razorpay Payment Gateway]
    PayChoice -->|COD| OrderPlaced[Order Status: PLACED]
    Razorpay --> OrderPlaced

    OrderPlaced --> ShopNotify[Shop Notified of New Order]
    ShopNotify --> ShopDecide{Shop Owner Action}
    
    ShopDecide -->|Reject| OrderCancelled[Order Cancelled & Refunded]
    ShopDecide -->|Accept| ShopPrep[Status: ACCEPTED_BY_SHOP -> PREPARING]

    ShopPrep --> PackPhoto[Shop Uploads Packing Photo]
    PackPhoto --> ReadyPickup[Status: READY_FOR_PICKUP]

    ReadyPickup --> DriverMatching[Celery Dispatch Engine Searches Nearby Drivers & Batches Parallel Orders]
    DriverMatching --> OfferSent{Driver Assignment Offer}
    
    OfferSent -->|Decline / Timeout 35s| NextDriver[Cascade to Next Nearest Driver]
    NextDriver --> OfferSent
    
    OfferSent -->|Accept| DriverAssigned[Status: PARTNER_ASSIGNED]

    DriverAssigned --> ArriveShop[Driver Arrives at Shop]
    ArriveShop --> VerifyPickup[Driver enters 4-digit Pickup OTP]
    VerifyPickup --> PickedUp[Status: PICKED_UP -> OUT_FOR_DELIVERY]

    PickedUp --> ReachCustomer[Driver Delivers Orders in Parallel Route]
    ReachCustomer --> VerifyDelivery[Customer Provides 4-digit Delivery OTP]
    VerifyDelivery --> Delivered[Status: DELIVERED & COMPLETED]

    Delivered --> Payout[Automated Wallet Payout Split]
    Payout --> End([Order Finished])
```

---

## 💰 4. Financial & Unit Economics Profitability Model

### 📊 Standard Order Delivery Fee Structure

Paasel maintains a transparent delivery fee model while enabling delivery partners to carry **multiple parallel orders** on single routes to maximize rider earnings.

| Order Metric | Fee Amount | Description |
| :--- | :---: | :--- |
| **Customer Delivery Fee Charged** | **₹34** | Flat transparent delivery fee for orders |
| **Delivery Partner Payout** | **₹25** | Direct rider payout per order |
| **Paasel Net Profit Margin** | **₹9** | **Pure platform gross margin saved per order** |

> 💡 **Multi-Order Parallel Batching**: Delivery partners can pick up and deliver 2 to 3 orders along the same route simultaneously. This increases rider earnings to **₹50–₹75+ per trip** while keeping delivery fast and efficient.

---

> [!NOTE]
> ### 💡 Strategic Growth Note: Free Delivery Promotion for Small Orders (<₹100)
> * **Market Gap & Opportunity**: Most local grocery buyers place frequent small orders (under ₹100, often purchasing under 10 items). Currently, **no quick-commerce player (Blinkit, Zepto, Swiggy) offers free delivery on orders under ₹100**.
> * **Growth Strategy**: Paasel is evaluating a **Free Delivery Promotional Offer** during the initial market launch for small orders under ₹100.
> * **Execution & Economics**: This promo will be subsidized using the **₹249/month Shop Subscription pool** and optimized via **parallel order batching** (where 2-3 small orders are batched together). This zero-delivery-fee advantage will drive viral user acquisition, explosive order volume, and unbeatable customer retention.

---

### 🏪 Single Shop Monthly Earnings Formula

* **Shop Subscription Plan**: **₹249 / month** per shop (0% sales commission).
* **Average Monthly Order Volume**: **50 orders per shop/month**.

$$\text{Monthly Net Profit per Shop} = \text{Shop Subscription (₹249)} + (\text{Monthly Orders (50)} \times \text{Net Margin (₹9)})$$

#### Single Shop Monthly Math Breakdown:
1. **Subscription Fee**: ₹249 / month
2. **Order Margin Profit (50 orders @ ₹9/order)**: $50 \times \text{₹9} = \mathbf{₹450}$
3. **Total Monthly Net Earnings per Shop**:
   $$\text{₹249} + \text{₹450} = \mathbf{₹699 / month}$$

---

### 📈 Scaled Earnings Calculation (Initial & Growth Months)

#### Scenario A: 100 Shops Onboarded (Initial Target)
* **Total Shops**: 100 Shops
* **Subscription Revenue**: $100 \times ₹249 = \mathbf{₹24,900 / \text{month}}$
* **Total Orders Delivered**: $100 \text{ shops} \times 50 \text{ orders} = \mathbf{5,000 \text{ orders / month}}$
* **Order Margin Earnings**: $5,000 \times ₹9 = \mathbf{₹45,000 / \text{month}}$
* **Total Monthly Gross Profit**:
  $$₹24,900 + ₹45,000 = \mathbf{₹69,900 / \text{month}} \quad (\sim \mathbf{₹8.38 \text{ Lakhs / year ARR}})$$

---

#### Scenario B: 150 Shops Onboarded (Growth Stage)
* **Total Shops**: 150 Shops
* **Subscription Revenue**: $150 \times ₹249 = \mathbf{₹37,350 / \text{month}}$
* **Total Orders Delivered**: $150 \text{ shops} \times 50 \text{ orders} = \mathbf{7,500 \text{ orders / month}}$
* **Order Margin Earnings**: $7,500 \times ₹9 = \mathbf{₹67,500 / \text{month}}$
* **Total Monthly Gross Profit**:
  $$₹37,350 + ₹67,500 = \mathbf{₹1,04,850 / \text{month}} \quad (\sim \mathbf{₹12.58 \text{ Lakhs / year ARR}})$$

---

### 💵 Comprehensive Financial Scale Projection Table

| Scale Metric | 1 Shop | 50 Shops | 100 Shops | 150 Shops | 300 Shops | 500 Shops |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Monthly Subscriptions (₹249/shop)** | ₹249 | ₹12,450 | ₹24,900 | ₹37,350 | ₹74,700 | ₹1,24,500 |
| **Monthly Orders (50 orders/shop)** | 50 | 2,500 | 5,000 | 7,500 | 15,000 | 25,000 |
| **Order Profit Margin (₹9/order)** | ₹450 | ₹22,500 | ₹45,000 | ₹67,500 | ₹1,35,000 | ₹2,25,000 |
| **Total Monthly Revenue** | **₹699** | **₹34,950** | **₹69,900** | **₹1,04,850** | **₹2,09,700** | **₹3,49,500** |
| **Annualized Net Earnings (ARR)** | **~₹8.4K** | **~₹4.19L** | **~₹8.38L** | **~₹12.58L** | **~₹25.16L** | **~₹41.94L** |

---

### 💳 Financial Revenue Flow & Cash Distribution Diagram

```mermaid
graph LR
    C[Customer Pays Item Price + ₹34 Fee] --> P[Paasel Payment Gateway / Razorpay Route]
    
    P -->|Item Price: 100%| S[Shopkeeper Wallet / Bank Account]
    P -->|Delivery Payout: ₹25| D[Delivery Partner Wallet]
    P -->|Net Margin: ₹9| Profit[Paasel Profit Pool]

    ShopSub[Shopkeeper Monthly Plan: ₹249] --> Profit

    subgraph Paasel Net Monthly Income
        Profit --> TotalEarnings["Total Monthly Revenue<br/>(₹249/shop Sub + ₹9/order Margin)"]
    end
```

---

## 🎯 Summary Conclusion

1. **Increased Merchant Value**: At **₹249/month**, shops get a complete digital store, ordering app, and delivery fleet for under ₹9/day.
2. **Competitive Free Delivery Edge**: Offering promotional free delivery on small orders (<₹100) will unlock massive order volume that no Quick-Commerce competitor currently captures.
3. **Solid Profitability Milestone**:
   * **100 Shops** generates **₹69,900 / month** (~₹8.38 Lakhs ARR).
   * **150 Shops** generates **₹1,04,850 / month** (~₹12.58 Lakhs ARR).
4. **Strong Scaling Potential**: Reaching **500 shops** generates **₹3,49,500 monthly net profit** (~₹41.94 Lakhs ARR).
