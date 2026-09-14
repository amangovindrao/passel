"""Add multi-role support, ledger fields, and multi-shop order parent/child columns.

Revision ID: 0005_unified_account_wallet_multishop
Revises: 0004_kyc_review

"""
from alembic import op

revision = "0005_unified_account_wallet_multishop"
down_revision = "0004_kyc_review"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1. Users: multi-role array
    op.execute(
        "ALTER TABLE users "
        "ADD COLUMN roles text[] NOT NULL DEFAULT '{}'::text[]"
    )

    # 2. Wallet Transactions: ledger audit fields
    op.execute(
        "ALTER TABLE wallet_transactions "
        "ALTER COLUMN type TYPE varchar(40), "
        "ADD COLUMN direction varchar(10) NOT NULL DEFAULT 'CREDIT', "
        "ADD COLUMN status varchar(20) NOT NULL DEFAULT 'COMPLETED', "
        "ADD COLUMN delivery_reference varchar(100), "
        "ADD COLUMN idempotency_key varchar(120), "
        "ADD COLUMN description text, "
        "ADD COLUMN metadata_json jsonb"
    )
    op.execute(
        "CREATE UNIQUE INDEX uq_wallet_txns_idempotency_key "
        "ON wallet_transactions(idempotency_key) "
        "WHERE idempotency_key IS NOT NULL"
    )

    # 3. Orders: parent order, wallet used, multi-shop flag
    op.execute(
        "ALTER TABLE orders "
        "ALTER COLUMN payment_mode TYPE varchar(20), "
        "ADD COLUMN parent_order_id uuid REFERENCES orders(id) ON DELETE CASCADE, "
        "ADD COLUMN wallet_amount_used_paise integer NOT NULL DEFAULT 0, "
        "ADD COLUMN is_multi_shop boolean NOT NULL DEFAULT false"
    )
    op.execute(
        "CREATE INDEX ix_orders_parent_order_id "
        "ON orders(parent_order_id)"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_orders_parent_order_id")
    op.execute(
        "ALTER TABLE orders "
        "DROP COLUMN is_multi_shop, "
        "DROP COLUMN wallet_amount_used_paise, "
        "DROP COLUMN parent_order_id"
    )
    op.execute("DROP INDEX IF EXISTS uq_wallet_txns_idempotency_key")
    op.execute(
        "ALTER TABLE wallet_transactions "
        "DROP COLUMN metadata_json, "
        "DROP COLUMN description, "
        "DROP COLUMN idempotency_key, "
        "DROP COLUMN delivery_reference, "
        "DROP COLUMN status, "
        "DROP COLUMN direction"
    )
    op.execute("ALTER TABLE users DROP COLUMN roles")
