# 💼 Paasel — Business Plan & Financial Growth Model

> **Paasel** is a next-generation hyperlocal grocery delivery marketplace built by **theScaleOn**. We empower local neighborhood Kirana stores to compete with Quick-Commerce giants through a zero-commission subscription model, delivering daily essentials within a 4 km radius in under 30 minutes.

---

## 🚀 Executive Summary

* **Company Name**: Paasel (by theScaleOn)
* **Industry**: Hyperlocal E-Commerce / Quick-Commerce Tech / Logistics
* **Core Product**: Triple-App Ecosystem (Customer, Shop Owner, Delivery Partner) + High-Concurrency FastAPI & PostGIS Engine.
* **Key Innovation**: Zero-commission subscription model (₹249/month per shop) replacing heavy 20-30% platform commissions.
* **Target Market**: Local Kirana store owners, recurring monthly ration buyers, and local delivery partners in Tier 1, 2, and 3 cities.

---

## ⚡ 1. The Market Problem

```mermaid
graph TD
    QC["Quick-Commerce Giants (Blinkit, Zepto, Swiggy)"]
    QC -->|20% - 30% Heavy Commission| K["Local Kirana Stores Squeezed Out"]
    QC -->|Dark Stores Bypass Stores| L["Neighborhood Businesses Dying"]
    QC -->|High Handling & Inflated Prices| C["Customers Overpaying"]
    QC -->|Low Payouts & Long Radius| R["Rider Dissatisfaction & High Churn"]
```

1. **Kirana Stores Being Erased**: Traditional local grocery shops are losing regular customers to dark-store quick commerce platforms.
2. **Exorbitant Platform Commissions**: Existing platforms charge 20% to 30% per order, making it impossible for small Kirana vendors to maintain profit margins.
3. **Price Inflation for Customers**: High platform fees and handling charges result in customers paying significantly higher prices for daily groceries.
4. **Unfair Logistics**: Delivery riders are underpaid and forced to cover excessive distances for low earnings.

---

## 💡 2. The Solution: Paasel Model

```mermaid
graph LR
    Shop["🏪 Local Kirana Shop<br/>(Pays ₹249/mo flat)"] --- Platform["⚡ Paasel Hyperlocal Engine<br/>(0% Shop Commission)"]
    Customer["🛒 Local Customer<br/>(Pays ₹34 Delivery Fee)"] --- Platform
    Rider["🛵 Local Rider<br/>(Earns ₹25 Payout + Parallel Orders)"] --- Platform
    Platform --> Profit["💰 Paasel Net Margin<br/>(₹9 per order)"]
```

* **Shop-First Zero Commission**: Shops keep 100% of their product sales. They pay only a flat **₹249/month subscription fee** (<₹9/day).
* **Transparent Delivery Pricing**: **₹34 customer delivery fee** (₹25 rider payout | **₹9 Paasel net profit**).
* **Multi-Order Parallel Batching**: Delivery partners deliver multiple orders on the same route simultaneously, boosting rider income to **₹50–₹75+ per trip**.
* **Built-in Quality Control**: Photo verification at packing and double OTP verification (Pickup OTP + Delivery OTP) to eliminate order disputes.

---

## 🔄 3. End-to-End Operational Workflows & Flowcharts

### A. Overall Triple-App System Workflow
```mermaid
flowchart TD
    subgraph CustomerApp["🛒 Customer Application"]
        C1[Browse Local Shops within 4km] --> C2[Select Grocery / Ration Items]
        C2 --> C3[Place Order & Choose Online / COD]
        C3 --> C4[Track Order & Receive 4-Digit Delivery OTP]
    end

    subgraph ShopApp["🏪 Shop Owner Application"]
        S1[Receive Order Alert] --> S2{Accept / Reject Order}
        S2 -->|Accept| S3[Pack Items & Upload Packing Photo]
        S3 --> S4[Mark Order: READY_FOR_PICKUP]
        S4 --> S5[Handover to Driver using 4-Digit Pickup OTP]
    end

    subgraph DispatchEngine["⚡ FastAPI + Redis Celery Dispatch Engine"]
        D1[Calculate Spatial Radius via PostGIS] --> D2[Batch Parallel Orders on Shared Routes]
        D2 --> D3[Send 35-Sec Offer to Nearest Online Driver]
    end

    subgraph DriverApp["🛵 Delivery Partner Application"]
        R1[Receive Batch Delivery Offer] --> R2[Accept Offer & Navigate to Shop]
        R2 --> R3[Verify Pickup OTP with Shop Owner]
        R3 --> R4[Deliver Items to Customer]
        R4 --> R5[Verify Delivery OTP with Customer & Complete]
    end

    C3 --> S1
    S4 --> D1
    D3 --> R1
    R5 --> Payout[Automated Wallet Payout Settlement]
```

---

### B. Order Packing & Photo Verification Flowchart
```mermaid
flowchart LR
    A[Order Accepted by Shop] --> B[Shopkeeper Packs Groceries]
    B --> C[Shopkeeper Takes Packing Photo via App]
    C --> D[Photo Uploaded & Verified by System]
    D --> E[Status Updated to READY_FOR_PICKUP]
    E --> F[Automated Driver Dispatch Triggered]
```

---

### C. Multi-Order Parallel Batching & Route Optimization Flowchart
```mermaid
flowchart TD
    O1[Order 1 Ready at Shop A] & O2[Order 2 Ready at Shop B Nearby] --> BatchEngine[Paasel Celery Route Engine]
    BatchEngine -->|Match Shared Drop-off Direction| MultiOffer[Batch Delivery Offer Sent to Rider]
    MultiOffer --> RiderAccept[Rider Accepts Multi-Order Batch]
    RiderAccept --> Pick1[Pickup Order 1] --> Pick2[Pickup Order 2]
    Pick2 --> Drop1[Deliver Order 1 & Verify OTP] --> Drop2[Deliver Order 2 & Verify OTP]
    Drop2 --> RiderPayout["Rider Earns ₹50 (2 x ₹25 Payout)<br/>Paasel Retains ₹18 Net Profit"]
```

---

### D. Double-OTP Security & Anti-Fraud Flowchart
```mermaid
flowchart TD
    subgraph PickupStage["Stage 1: Shop Pickup Security"]
        P1[Driver Arrives at Shop] --> P2[Shopkeeper Displays 4-Digit Pickup OTP]
        P2 --> P3[Driver Enters OTP in App]
        P3 -->|Valid OTP| P4[Status Changed to OUT_FOR_DELIVERY]
    end

    subgraph DeliveryStage["Stage 2: Customer Delivery Security"]
        D1[Driver Arrives at Customer Location] --> D2[Customer Shares 4-Digit Delivery OTP]
        D2 --> D3[Driver Enters OTP in App]
        D3 -->|Valid OTP| D4[Order Marked DELIVERED & COMPLETED]
    end

    P4 --> D1
    D4 --> WalletCredit[Instant Wallet Payout Triggered]
```

---

## 📊 4. Market Opportunity (TAM / SAM / SOM)

```
┌────────────────────────────────────────────────────────┐
│ TAM: $600 Billion                                      │
│ India Retail Grocery Market (12M+ Kirana Stores)       │
│ ┌────────────────────────────────────────────────────┐ │
│ │ SAM: $30 Billion                                   │ │
│ │ Tier 1/2/3 Hyperlocal Grocery Delivery Market      │ │
│ │ ┌────────────────────────────────────────────────┐ │ │
│ │ │ SOM: ₹50 Crore / Year                          │ │ │
│ │ │ Initial 5,000 Onboarded Stores (Next 18-24 Mo)  │ │ │
│ │ └────────────────────────────────────────────────┘ │ │
│ └────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────┘
```

---

## 💰 5. Unit Economics & Business Model

### A. Per-Order Unit Economics

```mermaid
pie title Delivery Fee Split (₹34 Fee)
    "Delivery Partner Payout (₹25)" : 74
    "Paasel Net Profit Margin (₹9)" : 26
```

| Component | Amount | Financial Impact |
| :--- | :---: | :--- |
| **Customer Delivery Fee Charged** | **₹34** | Transparent checkout delivery charge |
| **Delivery Partner Payout** | **₹25** | Instant rider wallet credit per order |
| **Paasel Net Profit Margin** | **₹9** | **Pure platform gross margin saved per order** |

> 🛵 **Rider Parallel Batching**: Riders can carry 2–3 orders per batch on shared routes, making **₹50–₹75+ per delivery run**, driving high rider retention and fast delivery.

---

> [[NOTE]]
> ### 💡 Strategic Growth Catalyst: Promotional Free Delivery on Small Orders (<₹100)
> * **Market Gap**: Most daily household grocery items are small transactions under ₹100 (purchasing under 10 daily items). **No competitor (Blinkit, Zepto, Swiggy) provides free delivery on orders under ₹100**.
> * **Growth Strategy**: Paasel will run a **Promotional Free Delivery Campaign** for small orders during market entry.
> * **Financial Engine**: Subsidized via the **₹249/month merchant subscription fund** and optimized through **multi-order parallel route batching**. This strategy eliminates purchase friction, drastically lowers CAC, and creates viral customer adoption.

---

### B. Single Shop Unit Economics
Assuming a typical Kirana store processes **50 orders per month**:

$$\text{Monthly Revenue per Shop} = \text{Subscription Fee (₹249)} + (\text{Monthly Orders (50)} \times \text{Net Profit Margin (₹9)})$$

* **Subscription Fee**: ₹249 / month
* **Order Profit Margin (50 orders @ ₹9/order)**: $50 \times \text{₹9} = \mathbf{₹450}$
* **Total Net Monthly Profit per Shop**: **₹699 / month**

---

### C. Scaled Financial Growth Projections

```mermaid
graph TD
    P1["Phase 1: 100 Shops<br/>₹69,900 / mo (~₹8.38L ARR)"] --> P2["Phase 2: 150 Shops<br/>₹1,04,850 / mo (~₹12.58L ARR)"]
    P2 --> P3["Phase 3: 500 Shops<br/>₹3,49,500 / mo (~₹41.94L ARR)"]
    P3 --> P4["Phase 4: 2,000 Shops<br/>₹13,98,000 / mo (~₹1.67 Cr ARR)"]
    P4 --> P5["Phase 5: 5,000 Shops<br/>₹34,95,000 / mo (~₹4.19 Cr ARR)"]
```

#### Detailed Financial Scaling Table:

| Metric | Phase 1 (100 Shops) | Phase 2 (150 Shops) | Phase 3 (500 Shops) | Phase 4 (2,000 Shops) | Phase 5 (5,000 Shops) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Monthly Subscription (₹249/shop)** | ₹24,900 | ₹37,350 | ₹1,24,500 | ₹4,98,000 | ₹12,45,000 |
| **Monthly Orders (50 orders/shop)** | 5,000 | 7,500 | 25,000 | 1,00,000 | 2,50,000 |
| **Order Profit Margin (₹9/order)** | ₹45,000 | ₹67,500 | ₹2,25,000 | ₹9,00,000 | ₹22,50,000 |
| **Total Monthly Gross Profit** | **₹69,900** | **₹1,04,850** | **₹3,49,500** | **₹13,98,000** | **₹34,95,000** |
| **Annualized Revenue (ARR)** | **~₹8.38 Lakhs** | **~₹12.58 Lakhs** | **~₹41.94 Lakhs** | **~₹1.67 Crores** | **~₹4.19 Crores** |

---

## 🛡️ 6. Technology Architecture & Competitive Moat

```mermaid
graph TD
    subgraph Frontend["📱 Triple Flutter Applications"]
        CApp["Customer App"]
        SApp["Shop App"]
        DApp["Delivery App"]
    end

    subgraph Backend["⚡ High-Performance Core Engine"]
        FastAPI["FastAPI Python Async Service"]
        PostGIS[("PostgreSQL 16 + PostGIS Spatial Engine")]
        Celery["Redis + Celery Parallel Dispatch Worker"]
    end

    subgraph Defense["🔒 Security & Anti-Fraud"]
        SupaAuth["Supabase Phone OTP & JWT"]
        PhotoProof["Packing & Pickup Photo Verification"]
        DoubleOTP["2-Step OTP Validation (Pickup + Delivery)"]
        SplitPay["Razorpay Route Split Payouts"]
    end

    Frontend --> Backend
    Backend --> Defense
```

1. **PostGIS Spatial Radius Indexing**: Exact 4 km geographic boundary matching preventing unfulfillable orders.
2. **Automated Celery Parallel Batch Engine**: Dispatches multi-order offers to online riders to deliver multiple orders on shared routes.
3. **Double OTP & Photo Verification**: Prevents order loss, fraud claims, and delivery disputes.
4. **Instant Split Settlement**: Razorpay Route instantly splits item costs to shops and delivery payouts to rider wallets.

---

## 🎯 7. Go-To-Market (GTM) Strategy

```mermaid
flowchart LR
    A["📍 Pin Code Cluster Strategy"] --> B["🏪 Direct Merchant Onboarding"]
    B --> C["📲 Shopkeeper QR Code Standees"]
    C --> D["🔄 Convert Offline Shoppers to Digital"]
    D --> E["📈 Organic Network Scale"]
```

1. **Pin-Code Clustering**: Launching in concentrated clusters of 50–100 shops per locality to maximize delivery rider density.
2. **Merchant Onboarding**: Partnering with local Kirana Merchant Associations with a zero-commission pitch.
3. **Shopkeeper-Driven Customer Acquisition**: Placing Paasel QR Code standees at checkout counters. Shops convert their existing offline customers into digital monthly orderers.

---

## 💸 8. Capital Requirement & Use of Funds

### Capital Requirement Target: ₹25,000,000 (₹25 Lakhs Seed Capital)

```mermaid
pie title Capital Deployment Allocation
    "Merchant & Customer Acquisition (40%)" : 40
    "Tech Infrastructure & Parallel Batch Scaling (30%)" : 30
    "Operations & Fleet Setup (20%)" : 20
    "Legal, Compliance & Reserve (10%)" : 10
```

* **40% Marketing & Merchant Onboarding**: Field onboarding agents, merchant QR standees, and localized customer acquisition.
* **30% Product & Engineering**: Parallel batching routing optimization, live tracking, and analytics dashboards.
* **20% Operations & Logistics**: Driver onboarding, fleet management, and regional customer support.
* **10% Compliance & Contingency**: Legal, licensing, payment gateway reserves, and administrative setup.

---

## 🏆 9. Key Milestones & Growth Roadmap

* **Month 1 - 3**: Onboard **100 - 150 Kirana Shops**, reach **₹69,900 - ₹1,04,850 monthly gross profit**.
* **Month 4 - 6**: Expand to **500 Kirana Shops**, reach **₹3.49 Lakhs monthly gross profit** (~₹42L ARR).
* **Month 7 - 12**: Scale to **2,000 Shops across 3 cities**, reach **₹1.67 Cr ARR milestone**.
* **Month 13 - 24**: Scale to **5,000+ Shops**, achieve **₹4.19 Crore+ ARR** and launch B2B inventory restocking features for shops.

---

## 🤝 Contact & Partnership

* **Company**: Paasel (by theScaleOn)
* **Repository**: [https://github.com/amangovindrao/passel](https://github.com/amangovindrao/passel)
* **Direct Contact**: `engg.aman7djp@gmail.com`
