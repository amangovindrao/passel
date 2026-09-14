"""Add delivery verification, 7-minute return system, and order additions tables and columns.

Revision ID: 0008_delivery_verification_returns_additions
Revises: 0007_production_hardening_orders_packages

"""
from alembic import op

revision = "0008_delivery_verification_returns_additions"
down_revision = "0007_production_hardening_orders_packages"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1. Orders table verification and addition columns
    op.execute(
        """
        ALTER TABLE orders
        ADD COLUMN IF NOT EXISTS handover_initiated_at TIMESTAMP WITH TIME ZONE,
        ADD COLUMN IF NOT EXISTS verification_deadline TIMESTAMP WITH TIME ZONE,
        ADD COLUMN IF NOT EXISTS verification_status VARCHAR(30) NOT NULL DEFAULT 'NOT_INITIATED',
        ADD COLUMN IF NOT EXISTS addition_window_status VARCHAR(30) NOT NULL DEFAULT 'ADDITION_OPEN';

        CREATE INDEX IF NOT EXISTS ix_orders_verification_status ON orders(verification_status);
        CREATE INDEX IF NOT EXISTS ix_orders_addition_window_status ON orders(addition_window_status);
        """
    )

    # 2. Order Additions table
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS order_additions (
            id UUID PRIMARY KEY,
            original_order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
            customer_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
            shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE RESTRICT,
            member_order_id UUID,
            group_session_id UUID,
            status VARCHAR(30) NOT NULL DEFAULT 'REQUESTED',
            item_total_paise INTEGER NOT NULL,
            delivery_fee_adjustment_paise INTEGER NOT NULL DEFAULT 0,
            total_addition_paise INTEGER NOT NULL,
            wallet_amount_used_paise INTEGER NOT NULL DEFAULT 0,
            external_amount_paise INTEGER NOT NULL DEFAULT 0,
            payment_status VARCHAR(20) NOT NULL DEFAULT 'pending',
            idempotency_key VARCHAR(36),
            created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
            updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
        );

        CREATE INDEX IF NOT EXISTS ix_order_additions_original_order_id ON order_additions(original_order_id);
        CREATE INDEX IF NOT EXISTS ix_order_additions_customer_id ON order_additions(customer_id);
        CREATE INDEX IF NOT EXISTS ix_order_additions_shop_id ON order_additions(shop_id);
        CREATE INDEX IF NOT EXISTS ix_order_additions_status ON order_additions(status);
        """
    )

    # 3. Order Addition Items table
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS order_addition_items (
            id UUID PRIMARY KEY,
            addition_id UUID NOT NULL REFERENCES order_additions(id) ON DELETE CASCADE,
            product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
            qty INTEGER NOT NULL,
            price_at_addition_paise INTEGER NOT NULL,
            availability_status VARCHAR(20) NOT NULL DEFAULT 'available',
            created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
            updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
        );

        CREATE INDEX IF NOT EXISTS ix_order_addition_items_addition_id ON order_addition_items(addition_id);
        CREATE INDEX IF NOT EXISTS ix_order_addition_items_product_id ON order_addition_items(product_id);
        """
    )

    # 4. Order Returns table
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS order_returns (
            id UUID PRIMARY KEY,
            order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
            order_item_id UUID NOT NULL REFERENCES order_items(id) ON DELETE CASCADE,
            customer_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
            shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE RESTRICT,
            product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
            group_package_id UUID REFERENCES group_order_packages(id) ON DELETE SET NULL,
            return_reason VARCHAR(30) NOT NULL,
            status VARCHAR(30) NOT NULL DEFAULT 'RETURN_REQUESTED',
            return_charge_payer VARCHAR(30) NOT NULL DEFAULT 'CUSTOMER',
            return_charge_paise INTEGER NOT NULL DEFAULT 0,
            refund_amount_paise INTEGER NOT NULL DEFAULT 0,
            customer_notes TEXT,
            evidence_photo_url TEXT,
            is_expired_item BOOLEAN NOT NULL DEFAULT FALSE,
            idempotency_key VARCHAR(36),
            created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
            updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
        );

        CREATE INDEX IF NOT EXISTS ix_order_returns_order_id ON order_returns(order_id);
        CREATE INDEX IF NOT EXISTS ix_order_returns_order_item_id ON order_returns(order_item_id);
        CREATE INDEX IF NOT EXISTS ix_order_returns_customer_id ON order_returns(customer_id);
        CREATE INDEX IF NOT EXISTS ix_order_returns_shop_id ON order_returns(shop_id);
        CREATE INDEX IF NOT EXISTS ix_order_returns_status ON order_returns(status);
        """
    )

    # 5. Merchant Quality Incidents table
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS merchant_quality_incidents (
            id UUID PRIMARY KEY,
            shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
            order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
            product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
            return_id UUID REFERENCES order_returns(id) ON DELETE SET NULL,
            incident_type VARCHAR(30) NOT NULL,
            severity VARCHAR(20) NOT NULL DEFAULT 'CRITICAL',
            refund_amount_paise INTEGER NOT NULL DEFAULT 0,
            return_cost_paise INTEGER NOT NULL DEFAULT 0,
            status VARCHAR(30) NOT NULL DEFAULT 'RECORDED',
            created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
            updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
        );

        CREATE INDEX IF NOT EXISTS ix_merchant_quality_incidents_shop_id ON merchant_quality_incidents(shop_id);
        CREATE INDEX IF NOT EXISTS ix_merchant_quality_incidents_order_id ON merchant_quality_incidents(order_id);
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DROP TABLE IF EXISTS merchant_quality_incidents;
        DROP TABLE IF EXISTS order_returns;
        DROP TABLE IF EXISTS order_addition_items;
        DROP TABLE IF EXISTS order_additions;
        ALTER TABLE orders
        DROP COLUMN IF EXISTS addition_window_status,
        DROP COLUMN IF EXISTS verification_status,
        DROP COLUMN IF EXISTS verification_deadline,
        DROP COLUMN IF EXISTS handover_initiated_at;
        """
    )
