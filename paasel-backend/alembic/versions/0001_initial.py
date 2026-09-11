"""Initial PostGIS schema — all Paasel domain tables.

Revision ID: 0001_initial
Revises: None
"""

from alembic import op
import sqlalchemy as sa

revision = "0001_initial"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Extensions
    op.execute("CREATE EXTENSION IF NOT EXISTS postgis")

    # ------- users & profiles -------
    op.execute("""
    CREATE TABLE users (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        phone varchar(20) NOT NULL UNIQUE,
        role varchar(20) NOT NULL,
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX ix_users_role ON users(role);
    """)

    op.execute("""
    CREATE TABLE customer_profiles (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id uuid NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
        name varchar(120) NOT NULL,
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
    );
    """)

    op.execute("""
    CREATE TABLE shop_owner_profiles (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id uuid NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
        name varchar(120) NOT NULL,
        kyc_status varchar(20) NOT NULL DEFAULT 'pending',
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
    );
    """)

    op.execute("""
    CREATE TABLE delivery_partner_profiles (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id uuid NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
        name varchar(120) NOT NULL,
        kyc_status varchar(20) NOT NULL DEFAULT 'pending',
        vehicle_type varchar(20) NOT NULL,
        is_online boolean NOT NULL DEFAULT false,
        current_location geography(Point, 4326),
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX ix_delivery_partner_profiles_location
        ON delivery_partner_profiles USING gist(current_location);
    """)

    # ------- addresses -------
    op.execute("""
    CREATE TABLE addresses (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        customer_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        label varchar(60) NOT NULL,
        location geography(Point, 4326) NOT NULL,
        address_text text NOT NULL,
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX ix_addresses_customer_id ON addresses(customer_id);
    CREATE INDEX ix_addresses_location ON addresses USING gist(location);
    """)

    # ------- shops & subscriptions -------
    op.execute("""
    CREATE TABLE subscription_plans (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        name varchar(60) NOT NULL UNIQUE,
        price_paise integer NOT NULL CHECK (price_paise >= 0),
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
    );
    """)

    op.execute("""
    CREATE TABLE shops (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        owner_id uuid NOT NULL UNIQUE REFERENCES users(id) ON DELETE RESTRICT,
        name varchar(160) NOT NULL,
        category varchar(80) NOT NULL,
        location geography(Point, 4326) NOT NULL,
        delivery_radius_km smallint NOT NULL DEFAULT 4,
        is_open boolean NOT NULL DEFAULT false,
        subscription_status varchar(20) NOT NULL DEFAULT 'trial',
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX ix_shops_location ON shops USING gist(location);
    """)

    op.execute("""
    CREATE TABLE shop_subscriptions (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        shop_id uuid NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
        plan_id uuid NOT NULL REFERENCES subscription_plans(id) ON DELETE RESTRICT,
        is_trial boolean NOT NULL DEFAULT false,
        trial_start_date timestamptz,
        trial_end_date timestamptz,
        razorpay_subscription_id varchar(100),
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX ix_shop_subscriptions_shop_id ON shop_subscriptions(shop_id);
    """)

    # ------- products -------
    op.execute("""
    CREATE TABLE products (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        shop_id uuid NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
        name varchar(160) NOT NULL,
        price_paise integer NOT NULL CHECK (price_paise >= 0),
        unit varchar(40) NOT NULL,
        stock_status varchar(20) NOT NULL DEFAULT 'available',
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX ix_products_shop_id ON products(shop_id);
    """)

    # ------- orders -------
    op.execute("""
    CREATE TABLE orders (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        customer_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
        shop_id uuid NOT NULL REFERENCES shops(id) ON DELETE RESTRICT,
        status varchar(40) NOT NULL,
        item_total_paise integer NOT NULL CHECK (item_total_paise >= 0),
        delivery_fee_paise integer NOT NULL CHECK (delivery_fee_paise >= 0),
        payment_mode varchar(10) NOT NULL,
        delivery_otp varchar(4) CHECK (
            delivery_otp IS NULL OR (length(delivery_otp) = 4 AND delivery_otp ~ '^[0-9]{4}$')
        ),
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX ix_orders_customer_id ON orders(customer_id);
    CREATE INDEX ix_orders_shop_id ON orders(shop_id);
    CREATE INDEX ix_orders_status ON orders(status);
    """)

    op.execute("""
    CREATE TABLE order_items (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        order_id uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
        product_id uuid NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
        qty integer NOT NULL CHECK (qty > 0),
        price_at_order_time_paise integer NOT NULL CHECK (price_at_order_time_paise >= 0),
        availability_status varchar(20) NOT NULL DEFAULT 'available',
        unavailable_reason text,
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX ix_order_items_order_id ON order_items(order_id);
    """)

    op.execute("""
    CREATE TABLE order_status_history (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        order_id uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
        status varchar(40) NOT NULL,
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX ix_order_status_history_order_id ON order_status_history(order_id);
    """)

    op.execute("""
    CREATE TABLE order_photos (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        order_id uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
        captured_by varchar(20) NOT NULL,
        stage varchar(20) NOT NULL,
        photo_url text NOT NULL,
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX ix_order_photos_order_id ON order_photos(order_id);
    """)

    # ------- delivery -------
    op.execute("""
    CREATE TABLE delivery_assignments (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        order_id uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
        partner_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
        trip_id uuid NOT NULL,
        pickup_code varchar(4) NOT NULL CHECK (
            length(pickup_code) = 4 AND pickup_code ~ '^[0-9]{4}$'
        ),
        assigned_at timestamptz NOT NULL DEFAULT now(),
        accepted_at timestamptz,
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX ix_delivery_assignments_order_id ON delivery_assignments(order_id);
    CREATE INDEX ix_delivery_assignments_partner_id ON delivery_assignments(partner_id);
    CREATE INDEX ix_delivery_assignments_trip_id ON delivery_assignments(trip_id);
    """)

    op.execute("""
    CREATE TABLE live_locations (
        partner_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
        location geography(Point, 4326) NOT NULL,
        updated_at timestamptz NOT NULL DEFAULT now(),
        created_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX ix_live_locations_location ON live_locations USING gist(location);
    """)

    # ------- payments & wallets -------
    op.execute("""
    CREATE TABLE payments (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        order_id uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
        razorpay_payment_id varchar(100),
        amount_paise integer NOT NULL CHECK (amount_paise >= 0),
        status varchar(20) NOT NULL,
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX ix_payments_order_id ON payments(order_id);
    """)

    op.execute("""
    CREATE TABLE refunds (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        order_id uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
        razorpay_refund_id varchar(100),
        amount_paise integer NOT NULL CHECK (amount_paise >= 0),
        reason text NOT NULL,
        status varchar(20) NOT NULL,
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX ix_refunds_order_id ON refunds(order_id);
    """)

    op.execute("""
    CREATE TABLE wallets (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        owner_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
        owner_type varchar(20) NOT NULL,
        balance_paise integer NOT NULL DEFAULT 0 CHECK (balance_paise >= 0),
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX ix_wallets_owner_id ON wallets(owner_id);
    """)

    op.execute("""
    CREATE TABLE wallet_transactions (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        wallet_id uuid NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
        type varchar(20) NOT NULL,
        amount_paise integer NOT NULL CHECK (amount_paise >= 0),
        order_id uuid REFERENCES orders(id) ON DELETE SET NULL,
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX ix_wallet_transactions_wallet_id ON wallet_transactions(wallet_id);
    """)

    # ------- ratings & disputes -------
    op.execute("""
    CREATE TABLE ratings (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        order_id uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
        rated_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
        rated_entity_type varchar(20) NOT NULL,
        score smallint NOT NULL CHECK (score >= 1 AND score <= 5),
        comment text,
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX ix_ratings_order_id ON ratings(order_id);
    """)

    op.execute("""
    CREATE TABLE disputes (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        order_id uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
        raised_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
        status varchar(20) NOT NULL,
        resolution text,
        linked_photo_ids uuid[],
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX ix_disputes_order_id ON disputes(order_id);
    """)

    # ------- seed subscription plans -------
    op.execute("""
    INSERT INTO subscription_plans (name, price_paise) VALUES
        ('Starter', 14900),
        ('Growth', 24900),
        ('Pro', 34900)
    ON CONFLICT (name) DO NOTHING;
    """)


def downgrade() -> None:
    tables = [
        "disputes", "ratings", "wallet_transactions", "wallets", "refunds",
        "payments", "live_locations", "delivery_assignments", "order_photos",
        "order_status_history", "order_items", "orders", "products",
        "shop_subscriptions", "shops", "subscription_plans", "addresses",
        "delivery_partner_profiles", "shop_owner_profiles", "customer_profiles",
        "users",
    ]
    for t in tables:
        op.execute(f"DROP TABLE IF EXISTS {t} CASCADE")
