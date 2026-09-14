"""Add group_order_sessions, group_order_members, and group_order_cart_items with private_cart_mode.

Revision ID: 0006_group_orders_private_cart_mode
Revises: 0005_unified_account_wallet_multishop

"""
from alembic import op

revision = "0006_group_orders_private_cart_mode"
down_revision = "0005_unified_account_wallet_multishop"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1. Group Order Sessions
    op.execute(
        """
        CREATE TABLE group_order_sessions (
            id UUID PRIMARY KEY,
            creator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            delivery_address_id UUID REFERENCES addresses(id) ON DELETE SET NULL,
            society_name VARCHAR(120) NOT NULL,
            status VARCHAR(30) NOT NULL DEFAULT 'OPEN',
            private_cart_mode BOOLEAN NOT NULL DEFAULT FALSE,
            closes_at TIMESTAMP WITH TIME ZONE,
            created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
            updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
        );
        CREATE INDEX ix_group_order_sessions_creator_id ON group_order_sessions(creator_id);
        CREATE INDEX ix_group_order_sessions_status ON group_order_sessions(status);
        """
    )

    # 2. Group Order Members
    op.execute(
        """
        CREATE TABLE group_order_members (
            id UUID PRIMARY KEY,
            session_id UUID NOT NULL REFERENCES group_order_sessions(id) ON DELETE CASCADE,
            user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            name VARCHAR(120) NOT NULL,
            is_creator BOOLEAN NOT NULL DEFAULT FALSE,
            status VARCHAR(30) NOT NULL DEFAULT 'joined',
            paid_amount_paise INTEGER NOT NULL DEFAULT 0,
            wallet_amount_used_paise INTEGER NOT NULL DEFAULT 0,
            payment_status VARCHAR(20) NOT NULL DEFAULT 'pending',
            created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
            updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
        );
        CREATE INDEX ix_group_order_members_session_id ON group_order_members(session_id);
        CREATE INDEX ix_group_order_members_user_id ON group_order_members(user_id);
        CREATE UNIQUE INDEX uq_group_order_member_session_user ON group_order_members(session_id, user_id);
        """
    )

    # 3. Group Order Cart Items
    op.execute(
        """
        CREATE TABLE group_order_cart_items (
            id UUID PRIMARY KEY,
            session_id UUID NOT NULL REFERENCES group_order_sessions(id) ON DELETE CASCADE,
            member_id UUID NOT NULL REFERENCES group_order_members(id) ON DELETE CASCADE,
            user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE RESTRICT,
            product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
            qty INTEGER NOT NULL,
            price_at_addition_paise INTEGER NOT NULL,
            created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
            updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
            CONSTRAINT nonneg_group_cart_qty CHECK (qty > 0),
            CONSTRAINT nonneg_group_cart_price CHECK (price_at_addition_paise >= 0)
        );
        CREATE INDEX ix_group_order_cart_items_session_id ON group_order_cart_items(session_id);
        CREATE INDEX ix_group_order_cart_items_member_id ON group_order_cart_items(member_id);
        CREATE INDEX ix_group_order_cart_items_user_id ON group_order_cart_items(user_id);
        CREATE INDEX ix_group_order_cart_items_shop_id ON group_order_cart_items(shop_id);
        CREATE INDEX ix_group_order_cart_items_product_id ON group_order_cart_items(product_id);
        """
    )


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS group_order_cart_items CASCADE")
    op.execute("DROP TABLE IF EXISTS group_order_members CASCADE")
    op.execute("DROP TABLE IF EXISTS group_order_sessions CASCADE")
