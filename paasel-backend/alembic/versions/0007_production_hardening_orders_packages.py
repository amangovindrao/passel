"""Add production hardening columns and tables for inventory reservations and group order packages.

Revision ID: 0007_production_hardening_orders_packages
Revises: 0006_group_orders_private_cart_mode

"""
from alembic import op

revision = "0007_production_hardening_orders_packages"
down_revision = "0006_group_orders_private_cart_mode"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1. Product stock_quantity
    op.execute(
        """
        ALTER TABLE products
        ADD COLUMN IF NOT EXISTS stock_quantity INTEGER NOT NULL DEFAULT 100;
        """
    )

    # 2. Order production hardening columns
    op.execute(
        """
        ALTER TABLE orders
        ADD COLUMN IF NOT EXISTS order_type VARCHAR(30) NOT NULL DEFAULT 'NORMAL_ORDER',
        ADD COLUMN IF NOT EXISTS delivery_status VARCHAR(30),
        ADD COLUMN IF NOT EXISTS external_amount_paise INTEGER NOT NULL DEFAULT 0,
        ADD COLUMN IF NOT EXISTS group_session_id UUID REFERENCES group_order_sessions(id) ON DELETE SET NULL,
        ADD COLUMN IF NOT EXISTS paid_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
        ADD COLUMN IF NOT EXISTS paid_by_role VARCHAR(30);

        CREATE INDEX IF NOT EXISTS ix_orders_group_session_id ON orders(group_session_id);
        CREATE INDEX IF NOT EXISTS ix_orders_order_type ON orders(order_type);
        """
    )

    # 3. Group order sessions deadlines & payment completion
    op.execute(
        """
        ALTER TABLE group_order_sessions
        ADD COLUMN IF NOT EXISTS join_deadline TIMESTAMP WITH TIME ZONE,
        ADD COLUMN IF NOT EXISTS cart_deadline TIMESTAMP WITH TIME ZONE,
        ADD COLUMN IF NOT EXISTS payment_deadline TIMESTAMP WITH TIME ZONE,
        ADD COLUMN IF NOT EXISTS locked_at TIMESTAMP WITH TIME ZONE,
        ADD COLUMN IF NOT EXISTS payment_complete BOOLEAN NOT NULL DEFAULT FALSE;
        """
    )

    # 4. Inventory Reservations table
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS inventory_reservations (
            id UUID PRIMARY KEY,
            order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
            product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
            qty INTEGER NOT NULL,
            status VARCHAR(30) NOT NULL DEFAULT 'RESERVED',
            expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
            created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
        );
        CREATE INDEX IF NOT EXISTS ix_inventory_reservations_order_id ON inventory_reservations(order_id);
        CREATE INDEX IF NOT EXISTS ix_inventory_reservations_product_id ON inventory_reservations(product_id);
        CREATE INDEX IF NOT EXISTS ix_inventory_reservations_status ON inventory_reservations(status);
        CREATE INDEX IF NOT EXISTS ix_inventory_reservations_expires_at ON inventory_reservations(expires_at);
        """
    )

    # 5. Group Order Packages table
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS group_order_packages (
            id UUID PRIMARY KEY,
            session_id UUID NOT NULL REFERENCES group_order_sessions(id) ON DELETE CASCADE,
            member_id UUID NOT NULL REFERENCES group_order_members(id) ON DELETE CASCADE,
            shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE RESTRICT,
            order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
            rider_id UUID REFERENCES users(id) ON DELETE SET NULL,
            pickup_status VARCHAR(30) NOT NULL DEFAULT 'PENDING',
            delivery_status VARCHAR(30) NOT NULL DEFAULT 'NOT_READY',
            handover_status VARCHAR(30) NOT NULL DEFAULT 'PENDING',
            handover_otp VARCHAR(4),
            handover_type VARCHAR(30) NOT NULL DEFAULT 'CAPTAIN_HANDOVER',
            created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
            updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
        );
        CREATE INDEX IF NOT EXISTS ix_group_order_packages_session_id ON group_order_packages(session_id);
        CREATE INDEX IF NOT EXISTS ix_group_order_packages_member_id ON group_order_packages(member_id);
        CREATE INDEX IF NOT EXISTS ix_group_order_packages_shop_id ON group_order_packages(shop_id);
        CREATE INDEX IF NOT EXISTS ix_group_order_packages_order_id ON group_order_packages(order_id);
        """
    )


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS group_order_packages CASCADE;")
    op.execute("DROP TABLE IF EXISTS inventory_reservations CASCADE;")
    op.execute(
        """
        ALTER TABLE group_order_sessions
        DROP COLUMN IF EXISTS join_deadline,
        DROP COLUMN IF EXISTS cart_deadline,
        DROP COLUMN IF EXISTS payment_deadline,
        DROP COLUMN IF EXISTS locked_at,
        DROP COLUMN IF EXISTS payment_complete;
        """
    )
    op.execute(
        """
        ALTER TABLE orders
        DROP COLUMN IF EXISTS order_type,
        DROP COLUMN IF EXISTS delivery_status,
        DROP COLUMN IF EXISTS external_amount_paise,
        DROP COLUMN IF EXISTS group_session_id,
        DROP COLUMN IF EXISTS paid_by_user_id,
        DROP COLUMN IF EXISTS paid_by_role;
        """
    )
    op.execute(
        """
        ALTER TABLE products
        DROP COLUMN IF EXISTS stock_quantity;
        """
    )
