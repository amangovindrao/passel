# 💼 Paasel — Investor Pitch Deck & Financial Growth Model

> **Paasel** is a next-generation hyperlocal grocery delivery marketplace built by **theScaleOn**. We empower local neighborhood Kirana stores to compete with Quick-Commerce giants through a zero-commission subscription model, delivering daily essentials within a 4 km radius in under 30 minutes.

---

## 🚀 Executive Summary

* **Company Name**: Paasel (by theScaleOn)
* **Industry**: Hyperlocal E-Commerce / Quick-Commerce Tech / Logistics
* **Core Product**: Triple-App Ecosystem (Customer, Shop Owner, Delivery Partner) + High-Concurrency FastAPI & PostGIS Engine.
* **Key Innovation**: Zero-commission subscription model (₹249/month per shop) replacing heavy 20-30% platform commissions.
* **Target Audience**: Local Kirana store owners, recurring monthly ration buyers, and local delivery partners in Tier 1, 2, and 3 cities.

---

## ⚡ 1. The Problem

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

## 💡 2. The Solution: Paasel

```mermaid
graph LR
    Shop["🏪 Local Kirana Shop<br/>(Pays ₹249/mo flat)"] --- Platform["⚡ Paasel Hyperlocal Engine<br/>(0% Shop Commission)"]
    Customer["🛒 Local Customer<br/>(Pays ₹34-49 Delivery Fee)"] --- Platform
    Rider["🛵 Local Rider<br/>(Earns ₹25-36 Payout + Parallel Orders)"] --- Platform
    Platform --> Profit["💰 Paasel Net Margin<br/>(₹9-13 per order)"]
```

* **Shop-First Zero Commission**: Shops keep 100% of their product sales. They pay only a flat **₹249/month subscription fee** (<₹9/day).
* **Tiered Hyperlocal Delivery**: 
  * Orders below ₹100: **₹49 delivery fee** (₹36 rider payout | **₹13 Paasel profit**).
  * Orders above ₹100: **₹34 delivery fee** (₹25 rider payout | **₹9 Paasel profit**).
* **Multi-Order Parallel Batching**: Delivery partners deliver multiple orders on the same route simultaneously, boosting rider income to **₹50–₹100+ per trip**.
* **Built-in Quality Control**: Photo verification at packing and double OTP verification (Pickup OTP + Delivery OTP) to eliminate order disputes.

---

## 📊 3. Market Opportunity (TAM / SAM / SOM)

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

## 💰 4. Unit Economics & Business Model

### A. Tiered Delivery Fee & Per-Order Unit Economics

```mermaid
pie title Average Delivery Fee Split (Average ₹41 Fee)
    "Delivery Partner Payout (₹30)" : 73
    "Paasel Net Profit Margin (₹11)" : 27
```

| Order Value Tier | Customer Fee | Rider Payout | Paasel Net Profit | Key Advantage |
| :--- | :---: | :---: | :---: | :--- |
| **Below ₹100 Order** | **₹49** | **₹36** | **₹13** | High margin on low ticket orders |
| **Above ₹100 Order** | **₹34** | **₹25** | **₹9** | High volume conversion incentive |

> 🛵 **Rider Parallel Batching**: Riders can carry 2–3 orders per batch on shared routes, making **₹50–₹100+ per delivery run**, driving high rider retention and fast delivery.

---

### B. Single Shop Unit Economics
Assuming a typical Kirana store processes **50 orders per month**:

$$\text{Monthly Revenue per Shop} = \text{Subscription Fee (₹249)} + (\text{Monthly Orders (50)} \times \text{Net Profit Margin})$$

* **Subscription Fee**: ₹249 / month
* **Order Profit Margin (50 orders/month)**:
  * Min Margin (Above ₹100 orders @ ₹9/order): $50 \times \text{₹9} = \mathbf{₹450}$
  * Avg Margin (Weighted blend @ ₹11/order): $50 \times \text{₹11} = \mathbf{₹550}$
  * Max Margin (Below ₹100 orders @ ₹13/order): $50 \times \text{₹13} = \mathbf{₹650}$
* **Total Net Monthly Profit per Shop**: **₹699 to ₹899 / month**

---

### C. Scaled Financial Growth Projections

```mermaid
graph TD
    P1["Phase 1: 100 Shops<br/>₹69,900 - ₹89,900 / mo (~₹10.7L ARR)"] --> P2["Phase 2: 150 Shops<br/>₹1,04,850 - ₹1,34,850 / mo (~₹16.1L ARR)"]
    P2 --> P3["Phase 3: 500 Shops<br/>₹3,49,500 - ₹4,49,500 / mo (~₹53.9L ARR)"]
    P3 --> P4["Phase 4: 2,000 Shops<br/>₹13,98,000 - ₹17,98,000 / mo (~₹2.15 Cr ARR)"]
    P4 --> P5["Phase 5: 5,000 Shops<br/>₹34.95L - ₹44.95L / mo (~₹5.39 Cr ARR)"]
```

#### Detailed Financial Scaling Table:

| Metric | Phase 1 (100 Shops) | Phase 2 (150 Shops) | Phase 3 (500 Shops) | Phase 4 (2,000 Shops) | Phase 5 (5,000 Shops) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Monthly Subscription (₹249/shop)** | ₹24,900 | ₹37,350 | ₹1,24,500 | ₹4,98,000 | ₹12,45,000 |
| **Monthly Orders (50 orders/shop)** | 5,000 | 7,500 | 25,000 | 1,00,000 | 2,50,000 |
| **Order Profit Margin (₹9 - ₹13)** | ₹45,000 - ₹65,000 | ₹67,500 - ₹97,500 | ₹2,25,000 - ₹3,25,000 | ₹9,00,000 - ₹13,00,000 | ₹22,50,000 - ₹32,50,000 |
| **Total Monthly Gross Profit** | **₹69,900 - ₹89,900** | **₹1,04,850 - ₹1,34,850** | **₹3,49,500 - ₹4,49,500** | **₹13,98,000 - ₹17,98,000** | **₹34,95,000 - ₹44,95,000** |
| **Annualized Revenue (ARR)** | **~₹8.38L - ₹10.78L** | **~₹12.58L - ₹16.18L** | **~₹41.94L - ₹53.94L** | **~₹1.67Cr - ₹2.15Cr** | **~₹4.19Cr - ₹5.39Cr** |

---

## 🛡️ 5. Technology Architecture & Competitive Moat

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

## 🎯 6. Go-To-Market (GTM) Strategy

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

## 💸 7. Investment Ask & Use of Funds

### Funding Target: ₹25,000,000 (₹25 Lakhs Seed Capital)

```mermaid
pie title Use of Funds Allocation
    "Merchant & Customer Acquisition (40%)" : 40
    "Tech Infrastructure & Parallel Batch Scaling (30%)" : 30
    "Operations & Fleet Setup (20%)" : 20
    "Legal, Compliance & Reserve (10%)" : 10
```

* **40% Marketing & Sales**: Field onboarding agents, merchant QR standees, and localized customer acquisition.
* **30% Product & Engineering**: Parallel batching routing optimization, live tracking, and analytics dashboards.
* **20% Operations & Logistics**: Driver onboarding, fleet management, and regional customer support.
* **10% Compliance & Contingency**: Legal, licensing, payment gateway reserves, and administrative setup.

---

## 🏆 8. Key Milestones & Roadmap

* **Month 1 - 3**: Onboard **100 - 150 Kirana Shops**, reach **₹1.0 Lakh - ₹1.35 Lakhs monthly gross profit**.
* **Month 4 - 6**: Expand to **500 Kirana Shops**, reach **₹3.5 Lakhs - ₹4.5 Lakhs monthly gross profit** (~₹50L+ ARR).
* **Month 7 - 12**: Scale to **2,000 Shops across 3 cities**, reach **₹1.6 Cr - ₹2.1 Cr ARR milestone**.
* **Month 13 - 24**: Scale to **5,000+ Shops**, achieve **₹5.0 Crore+ ARR** and launch B2B inventory restocking features for shops.

---

## 🤝 Contact Information

* **Company**: Paasel (by theScaleOn)
* **Website / Repo**: [https://github.com/amangovindrao/passel](https://github.com/amangovindrao/passel)
* **Pitch Contact**: `engg.aman7djp@gmail.com`
