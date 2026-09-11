import sys
import os
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.enum.text import PP_ALIGN
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE

def build_presentation(output_path):
    prs = Presentation()
    prs.slide_width = Inches(13.333)
    prs.slide_height = Inches(7.5)
    blank_layout = prs.slide_layouts[6]

    # Color Palette
    BG_DARK = RGBColor(15, 23, 42)       # Slate 900
    CARD_BG = RGBColor(30, 41, 59)      # Slate 800
    TEXT_LIGHT = RGBColor(248, 250, 252) # Slate 50
    TEXT_MUTED = RGBColor(148, 163, 184)# Slate 400
    ACCENT_GREEN = RGBColor(16, 185, 129)# Emerald 500
    ACCENT_GOLD = RGBColor(245, 158, 11) # Amber 500
    ACCENT_BLUE = RGBColor(59, 130, 246) # Blue 500
    BORDER_COLOR = RGBColor(51, 65, 85) # Slate 700

    def add_blank_slide_with_bg(bg_color=BG_DARK):
        slide = prs.slides.add_slide(blank_layout)
        bg = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, Inches(13.333), Inches(7.5))
        bg.fill.solid()
        bg.fill.fore_color.rgb = bg_color
        bg.line.fill.background()
        return slide

    def add_header(slide, title_text, category_text="PAASEL BUSINESS PLAN"):
        # Category Tag
        cat_box = slide.shapes.add_textbox(Inches(0.8), Inches(0.4), Inches(11.7), Inches(0.4))
        tf_cat = cat_box.text_frame
        tf_cat.word_wrap = True
        p_cat = tf_cat.paragraphs[0]
        p_cat.text = category_text.upper()
        p_cat.font.size = Pt(11)
        p_cat.font.bold = True
        p_cat.font.color.rgb = ACCENT_GREEN

        # Main Title
        title_box = slide.shapes.add_textbox(Inches(0.8), Inches(0.7), Inches(11.7), Inches(0.8))
        tf_title = title_box.text_frame
        tf_title.word_wrap = True
        p_title = tf_title.paragraphs[0]
        p_title.text = title_text
        p_title.font.size = Pt(24)
        p_title.font.bold = True
        p_title.font.color.rgb = TEXT_LIGHT

    # -------------------------------------------------------------
    # SLIDE 1: Title Slide
    # -------------------------------------------------------------
    slide1 = add_blank_slide_with_bg()
    
    # Hero Title Box
    tb = slide1.shapes.add_textbox(Inches(1.0), Inches(2.2), Inches(11.3), Inches(3.5))
    tf = tb.text_frame
    tf.word_wrap = True
    
    p0 = tf.paragraphs[0]
    p0.text = "PAASEL"
    p0.font.size = Pt(48)
    p0.font.bold = True
    p0.font.color.rgb = ACCENT_GREEN
    p0.space_after = Pt(10)
    
    p1 = tf.add_paragraph()
    p1.text = "Business Plan & Financial Growth Model"
    p1.font.size = Pt(28)
    p1.font.bold = True
    p1.font.color.rgb = TEXT_LIGHT
    p1.space_after = Pt(15)
    
    p2 = tf.add_paragraph()
    p2.text = "Empowering Local Kirana Stores through a Zero-Commission Hyperlocal Delivery Platform"
    p2.font.size = Pt(16)
    p2.font.color.rgb = TEXT_MUTED
    p2.space_after = Pt(30)
    
    p3 = tf.add_paragraph()
    p3.text = "Presented by theScaleOn  |  engg.aman7djp@gmail.com"
    p3.font.size = Pt(14)
    p3.font.bold = True
    p3.font.color.rgb = ACCENT_GOLD

    # -------------------------------------------------------------
    # SLIDE 2: Executive Summary
    # -------------------------------------------------------------
    slide2 = add_blank_slide_with_bg()
    add_header(slide2, "Executive Summary — High-Volume Hyperlocal Model")
    
    cards_data = [
        ("🏪 Zero Commission for Shops", "Shops pay a flat ₹249/month subscription instead of losing 20-30% margin to dark stores. 100% item revenue stays with shopkeepers."),
        ("🛵 Parallel Multi-Order Batching", "Riders deliver 2-3 orders per batch along shared routes, boosting rider payouts to ₹50–₹75+ per run while ensuring fast 30-min delivery."),
        ("📊 Transparent Pricing & Margin", "Flat ₹34 customer fee, ₹25 rider payout, leaving ₹9 pure net profit per order for Paasel. Predictable, positive unit economics from Day 1."),
        ("🛡️ Enterprise Fraud Defense", "Double-OTP security (Shop Pickup OTP + Customer Delivery OTP) + required packing photo proof eliminate delivery claims and losses.")
    ]
    
    coords = [(0.8, 1.8), (6.8, 1.8), (0.8, 4.4), (6.8, 4.4)]
    for (x, y), (title, desc) in zip(coords, cards_data):
        shape = slide2.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(x), Inches(y), Inches(5.7), Inches(2.3))
        shape.fill.solid()
        shape.fill.fore_color.rgb = CARD_BG
        shape.line.color.rgb = BORDER_COLOR
        shape.line.width = Pt(1)
        
        tf = shape.text_frame
        tf.word_wrap = True
        tf.margin_left = Inches(0.25)
        tf.margin_right = Inches(0.25)
        tf.margin_top = Inches(0.2)
        
        p = tf.paragraphs[0]
        p.text = title
        p.font.size = Pt(16)
        p.font.bold = True
        p.font.color.rgb = ACCENT_GREEN
        p.space_after = Pt(8)
        
        p_body = tf.add_paragraph()
        p_body.text = desc
        p_body.font.size = Pt(13)
        p_body.font.color.rgb = TEXT_LIGHT

    # -------------------------------------------------------------
    # SLIDE 3: The Market Problem
    # -------------------------------------------------------------
    slide3 = add_blank_slide_with_bg()
    add_header(slide3, "The Problem — Traditional Retail Under Siege")
    
    problems = [
        ("01", "Kirana Stores Being Erased", "Quick-Commerce giants (Blinkit, Zepto, Swiggy) bypass local retail stores using dark warehouses, destroying neighborhood businesses."),
        ("02", "Exorbitant 20-30% Commissions", "Existing aggregator platforms charge 20% to 30% per order, eating up the thin margins of small grocery merchants."),
        ("03", "Customer Price Inflation", "High platform fees and hidden handling charges force customers to pay significantly inflated prices for basic household goods."),
        ("04", "Rider Underpayment & Churn", "Delivery partners face low per-order payouts and long delivery radiuses, leading to high driver frustration and fleet turnover.")
    ]
    
    for i, (num, headline, text) in enumerate(problems):
        y_pos = 1.7 + (i * 1.3)
        shape = slide3.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(0.8), Inches(y_pos), Inches(11.733), Inches(1.15))
        shape.fill.solid()
        shape.fill.fore_color.rgb = CARD_BG
        shape.line.color.rgb = BORDER_COLOR
        
        tf = shape.text_frame
        tf.word_wrap = True
        tf.margin_left = Inches(0.3)
        tf.margin_top = Inches(0.15)
        
        p = tf.paragraphs[0]
        p.text = f"{num}. {headline}"
        p.font.size = Pt(16)
        p.font.bold = True
        p.font.color.rgb = ACCENT_GOLD
        p.space_after = Pt(4)
        
        p2 = tf.add_paragraph()
        p2.text = text
        p2.font.size = Pt(13)
        p2.font.color.rgb = TEXT_LIGHT

    # -------------------------------------------------------------
    # SLIDE 4: End-to-End Operational Workflow
    # -------------------------------------------------------------
    slide4 = add_blank_slide_with_bg()
    add_header(slide4, "End-to-End Operational Workflow")
    
    steps = [
        ("Step 1: Order Placement", "Customer selects items from nearby Kirana (<4km) & receives 4-digit Delivery OTP."),
        ("Step 2: Packing Proof", "Shopkeeper accepts order, packs items, and uploads packing photo via Shop App."),
        ("Step 3: Route Batching", "Celery dispatch engine batches parallel orders on shared routes & offers to nearest rider."),
        ("Step 4: Pickup OTP", "Rider arrives at shop & verifies 4-digit Pickup OTP with shopkeeper before takeoff."),
        ("Step 5: Safe Delivery", "Rider delivers order, customer verifies Delivery OTP, triggering instant wallet split.")
    ]
    
    for i, (stitle, sdesc) in enumerate(steps):
        x_pos = 0.8 + (i * 2.38)
        shape = slide4.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(x_pos), Inches(2.2), Inches(2.2), Inches(4.3))
        shape.fill.solid()
        shape.fill.fore_color.rgb = CARD_BG
        shape.line.color.rgb = ACCENT_BLUE if i%2==0 else ACCENT_GREEN
        shape.line.width = Pt(1.5)
        
        tf = shape.text_frame
        tf.word_wrap = True
        tf.margin_left = Inches(0.15)
        tf.margin_right = Inches(0.15)
        tf.margin_top = Inches(0.2)
        
        p = tf.paragraphs[0]
        p.text = stitle
        p.font.size = Pt(14)
        p.font.bold = True
        p.font.color.rgb = ACCENT_GOLD
        p.space_after = Pt(10)
        
        p2 = tf.add_paragraph()
        p2.text = sdesc
        p2.font.size = Pt(12)
        p2.font.color.rgb = TEXT_LIGHT

    # -------------------------------------------------------------
    # SLIDE 5: Strategic Growth Note — Free Delivery Promo
    # -------------------------------------------------------------
    slide5 = add_blank_slide_with_bg()
    add_header(slide5, "Growth Strategy — Free Delivery for Orders <₹100")
    
    # Strategic Note Banner Box
    banner = slide5.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(0.8), Inches(1.8), Inches(11.733), Inches(4.8))
    banner.fill.solid()
    banner.fill.fore_color.rgb = CARD_BG
    banner.line.color.rgb = ACCENT_GOLD
    banner.line.width = Pt(2)
    
    tf = banner.text_frame
    tf.word_wrap = True
    tf.margin_left = Inches(0.4)
    tf.margin_right = Inches(0.4)
    tf.margin_top = Inches(0.3)
    
    p = tf.paragraphs[0]
    p.text = "💡 STRATEGIC COMPETITIVE GAP & GROWTH CATALYST"
    p.font.size = Pt(18)
    p.font.bold = True
    p.font.color.rgb = ACCENT_GOLD
    p.space_after = Pt(15)
    
    bullets = [
        "Untapped Small-Ticket Market: Over 70% of daily Kirana purchases are small orders under ₹100 (1 to 5 daily essential items).",
        "Competitor Deficit: Currently, NO Quick-Commerce competitor (Blinkit, Zepto, Swiggy) offers free delivery on orders under ₹100.",
        "Viral User Acquisition: Paasel will offer a Promotional Free Delivery Campaign for small orders during market launch to drive explosive adoption.",
        "Financial Subsidization Engine: Promos are funded through the ₹249/month merchant subscription pool and optimized via multi-order parallel route batching.",
        "Unbeatable Retention: Free delivery on small daily items creates habit-forming customer loyalty and unmatched market share."
    ]
    
    for b in bullets:
        pb = tf.add_paragraph()
        pb.text = "• " + b
        pb.font.size = Pt(14)
        pb.font.color.rgb = TEXT_LIGHT
        pb.space_after = Pt(10)

    # -------------------------------------------------------------
    # SLIDE 6: Unit Economics & Per-Shop Math
    # -------------------------------------------------------------
    slide6 = add_blank_slide_with_bg()
    add_header(slide6, "Unit Economics & Single Shop Profit Model")
    
    # Left Card: Delivery Fee Breakdown
    card1 = slide6.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(0.8), Inches(1.8), Inches(5.6), Inches(4.8))
    card1.fill.solid()
    card1.fill.fore_color.rgb = CARD_BG
    card1.line.color.rgb = ACCENT_GREEN
    card1.line.width = Pt(1.5)
    
    tf1 = card1.text_frame
    tf1.word_wrap = True
    tf1.margin_left = Inches(0.3)
    tf1.margin_top = Inches(0.3)
    
    p = tf1.paragraphs[0]
    p.text = "📦 Per-Order Fee Breakdown"
    p.font.size = Pt(18)
    p.font.bold = True
    p.font.color.rgb = ACCENT_GREEN
    p.space_after = Pt(15)
    
    items1 = [
        ("Customer Delivery Fee:", "₹34 (Flat transparent fee)"),
        ("Delivery Partner Payout:", "₹25 (Instant wallet credit)"),
        ("Paasel Net Margin:", "₹9 / order (Pure gross profit)"),
        ("Rider Multi-Batching:", "Earns ₹50 - ₹75+ per trip across 2-3 parallel orders")
    ]
    for lbl, val in items1:
        p_l = tf1.add_paragraph()
        p_l.text = f"{lbl} {val}"
        p_l.font.size = Pt(14)
        p_l.font.color.rgb = TEXT_LIGHT
        p_l.space_after = Pt(10)
        
    # Right Card: Single Shop Monthly Math
    card2 = slide6.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(6.9), Inches(1.8), Inches(5.6), Inches(4.8))
    card2.fill.solid()
    card2.fill.fore_color.rgb = CARD_BG
    card2.line.color.rgb = ACCENT_GOLD
    card2.line.width = Pt(1.5)
    
    tf2 = card2.text_frame
    tf2.word_wrap = True
    tf2.margin_left = Inches(0.3)
    tf2.margin_top = Inches(0.3)
    
    p = tf2.paragraphs[0]
    p.text = "🏪 Single Shop Monthly Earnings"
    p.font.size = Pt(18)
    p.font.bold = True
    p.font.color.rgb = ACCENT_GOLD
    p.space_after = Pt(15)
    
    items2 = [
        ("Monthly Shop Subscription:", "₹249 / month (<₹9/day)"),
        ("Monthly Order Volume:", "50 orders / shop"),
        ("Order Margin Earnings:", "50 orders x ₹9 = ₹450 / month"),
        ("Total Net Profit / Shop:", "₹249 + ₹450 = ₹699 / month net profit")
    ]
    for lbl, val in items2:
        p_l = tf2.add_paragraph()
        p_l.text = f"{lbl} {val}"
        p_l.font.size = Pt(14)
        p_l.font.color.rgb = TEXT_LIGHT
        p_l.space_after = Pt(10)

    # -------------------------------------------------------------
    # SLIDE 7: Financial Scaling Projections
    # -------------------------------------------------------------
    slide7 = add_blank_slide_with_bg()
    add_header(slide7, "Financial Scaling & Growth Projections")
    
    # Table of scaling
    rows, cols = 6, 6
    left, top, width, height = Inches(0.8), Inches(1.8), Inches(11.733), Inches(4.8)
    table_shape = slide7.shapes.add_table(rows, cols, left, top, width, height)
    table = table_shape.table
    
    headers = ["Scale Phase", "Active Shops", "Monthly Orders", "Subscription (₹249)", "Order Margin (₹9)", "Monthly Profit (ARR)"]
    data = [
        ["Phase 1 (Target)", "100 Shops", "5,000 orders", "₹24,900", "₹45,000", "₹69,900 (~₹8.38 Lakhs)"],
        ["Phase 2 (Growth)", "150 Shops", "7,500 orders", "₹37,350", "₹67,500", "₹1,04,850 (~₹12.58 Lakhs)"],
        ["Phase 3 (Expansion)", "500 Shops", "25,000 orders", "₹1,24,500", "₹2,25,000", "₹3,49,500 (~₹41.94 Lakhs)"],
        ["Phase 4 (City Scale)", "2,000 Shops", "1,00,000 orders", "₹4,98,000", "₹9,00,000", "₹13,98,000 (~₹1.67 Crores)"],
        ["Phase 5 (Multi-City)", "5,000 Shops", "2,50,000 orders", "₹12,45,000", "₹22,50,000", "₹34,95,000 (~₹4.19 Crores)"]
    ]
    
    for c_idx, h_text in enumerate(headers):
        cell = table.cell(0, c_idx)
        cell.fill.solid()
        cell.fill.fore_color.rgb = ACCENT_GREEN
        p = cell.text_frame.paragraphs[0]
        p.text = h_text
        p.font.size = Pt(13)
        p.font.bold = True
        p.font.color.rgb = BG_DARK
        
    for r_idx, row_values in enumerate(data):
        for c_idx, val in enumerate(row_values):
            cell = table.cell(r_idx + 1, c_idx)
            cell.fill.solid()
            cell.fill.fore_color.rgb = CARD_BG if r_idx%2==0 else RGBColor(20, 30, 48)
            p = cell.text_frame.paragraphs[0]
            p.text = val
            p.font.size = Pt(12)
            p.font.color.rgb = TEXT_LIGHT

    # -------------------------------------------------------------
    # SLIDE 8: Technology Moat & Defense
    # -------------------------------------------------------------
    slide8 = add_blank_slide_with_bg()
    add_header(slide8, "Technology Stack & Competitive Moat")
    
    tech_cards = [
        ("📍 PostGIS 4km Spatial Engine", "Strict geographic spatial indexing prevents unfulfillable delivery radiuses and keeps latency under 30 mins."),
        ("⚡ Redis & Celery Dispatch Engine", "High-concurrency worker engine evaluates multi-order parallel routes & cascades 35-sec driver offers automatically."),
        ("🔒 Double OTP Security", "Requires 4-digit Pickup OTP from shopkeeper and 4-digit Delivery OTP from customer, making fraud impossible."),
        ("💳 Razorpay Route Split Settlement", "Automated split engine routes item sales to shop accounts, delivery payouts to rider wallets, and platform margin to Paasel.")
    ]
    
    coords = [(0.8, 1.8), (6.8, 1.8), (0.8, 4.4), (6.8, 4.4)]
    for (x, y), (title, desc) in zip(coords, tech_cards):
        shape = slide8.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(x), Inches(y), Inches(5.7), Inches(2.3))
        shape.fill.solid()
        shape.fill.fore_color.rgb = CARD_BG
        shape.line.color.rgb = BORDER_COLOR
        
        tf = shape.text_frame
        tf.word_wrap = True
        tf.margin_left = Inches(0.25)
        tf.margin_top = Inches(0.2)
        
        p = tf.paragraphs[0]
        p.text = title
        p.font.size = Pt(16)
        p.font.bold = True
        p.font.color.rgb = ACCENT_BLUE
        p.space_after = Pt(8)
        
        p_body = tf.add_paragraph()
        p_body.text = desc
        p_body.font.size = Pt(13)
        p_body.font.color.rgb = TEXT_LIGHT

    # -------------------------------------------------------------
    # SLIDE 9: Capital Deployment
    # -------------------------------------------------------------
    slide9 = add_blank_slide_with_bg()
    add_header(slide9, "Capital Deployment & Growth Allocation")
    
    allocations = [
        ("40%", "Merchant & Customer Acquisition", "Field onboarding teams, Kirana merchant standees, and localized launch marketing."),
        ("30%", "Tech & Parallel Route Optimization", "Refining AI driver batching algorithms, live tracking, and analytics dashboards."),
        ("20%", "Operations & Logistics Setup", "Fleet onboarding, regional operational managers, and customer support infrastructure."),
        ("10%", "Legal, Compliance & Reserve", "Licensing, payment gateway reserves, and administrative contingency buffer.")
    ]
    
    for i, (pct, title, desc) in enumerate(allocations):
        y_pos = 1.7 + (i * 1.3)
        shape = slide9.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(0.8), Inches(y_pos), Inches(11.733), Inches(1.15))
        shape.fill.solid()
        shape.fill.fore_color.rgb = CARD_BG
        shape.line.color.rgb = ACCENT_GOLD if i==0 else BORDER_COLOR
        
        tf = shape.text_frame
        tf.word_wrap = True
        tf.margin_left = Inches(0.3)
        tf.margin_top = Inches(0.15)
        
        p = tf.paragraphs[0]
        p.text = f"{pct} — {title}"
        p.font.size = Pt(16)
        p.font.bold = True
        p.font.color.rgb = ACCENT_GOLD
        p.space_after = Pt(4)
        
        p2 = tf.add_paragraph()
        p2.text = desc
        p2.font.size = Pt(13)
        p2.font.color.rgb = TEXT_LIGHT

    # -------------------------------------------------------------
    # SLIDE 10: Conclusion & Contact
    # -------------------------------------------------------------
    slide10 = add_blank_slide_with_bg()
    
    shape = slide10.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(1.5), Inches(1.5), Inches(10.333), Inches(4.5))
    shape.fill.solid()
    shape.fill.fore_color.rgb = CARD_BG
    shape.line.color.rgb = ACCENT_GREEN
    shape.line.width = Pt(2)
    
    tf = shape.text_frame
    tf.word_wrap = True
    tf.margin_left = Inches(0.5)
    tf.margin_top = Inches(0.4)
    
    p = tf.paragraphs[0]
    p.text = "Join Us in Building the Future of Hyperlocal Retail"
    p.font.size = Pt(24)
    p.font.bold = True
    p.font.color.rgb = ACCENT_GREEN
    p.space_after = Pt(20)
    
    lines = [
        "• Empowering 12+ Million Kirana Stores across India",
        "• Highly Profitable & Scalable Unit Economics from Day 1",
        "• Production-Ready Technology Stack (Flutter + FastAPI + PostGIS)",
        "",
        "Direct Contact: engg.aman7djp@gmail.com",
        "Repository: https://github.com/amangovindrao/passel"
    ]
    
    for line in lines:
        p_l = tf.add_paragraph()
        p_l.text = line
        if "Direct Contact" in line or "Repository" in line:
            p_l.font.size = Pt(16)
            p_l.font.bold = True
            p_l.font.color.rgb = ACCENT_GOLD
        else:
            p_l.font.size = Pt(15)
            p_l.font.color.rgb = TEXT_LIGHT
        p_l.space_after = Pt(8)

    prs.save(output_path)
    print(f"Successfully generated PowerPoint presentation at: {output_path}")

if __name__ == "__main__":
    out_file = sys.argv[1] if len(sys.argv) > 1 else "Paasel_Business_Plan_Presentation.pptx"
    build_presentation(out_file)
