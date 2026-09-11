"""Reconcile lifecycle, payments, and settlement schema.

Revision ID: 0002_integration_hardening
Revises: 0001_initial
"""
from alembic import op

revision = "0002_integration_hardening"
down_revision = "0001_initial"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("UPDATE shop_owner_profiles SET kyc_status = 'approved' WHERE kyc_status = 'verified'")
    op.execute("ALTER TABLE delivery_partner_profiles ADD COLUMN razorpay_linked_account_id varchar(100)")
    op.execute("ALTER TABLE shops ADD COLUMN razorpay_linked_account_id varchar(100)")
    op.execute("ALTER TABLE orders ADD COLUMN payment_status varchar(20) NOT NULL DEFAULT 'pending', ADD COLUMN idempotency_key varchar(36), ADD COLUMN razorpay_order_id varchar(100), ADD COLUMN matching_requires_attention boolean NOT NULL DEFAULT false, ADD COLUMN cancellation_deduction_paise integer NOT NULL DEFAULT 0 CHECK (cancellation_deduction_paise >= 0)")
    op.execute("CREATE UNIQUE INDEX uq_orders_idempotency_key ON orders(idempotency_key) WHERE idempotency_key IS NOT NULL")
    op.execute("ALTER TABLE delivery_assignments ADD COLUMN status varchar(20) NOT NULL DEFAULT 'offered', ADD COLUMN declined_at timestamptz, ADD COLUMN expired_at timestamptz, ADD COLUMN timeout_task_id varchar(100), ADD COLUMN cascade_count smallint NOT NULL DEFAULT 0")
    op.execute("UPDATE delivery_assignments SET status = 'accepted' WHERE accepted_at IS NOT NULL")
    op.execute("CREATE INDEX ix_delivery_assignments_status ON delivery_assignments(status)")
    op.execute("ALTER TABLE payments ADD COLUMN razorpay_order_id varchar(100)")
    op.execute("CREATE UNIQUE INDEX uq_payments_razorpay_payment_id ON payments(razorpay_payment_id) WHERE razorpay_payment_id IS NOT NULL")
    op.execute("CREATE UNIQUE INDEX uq_refunds_razorpay_refund_id ON refunds(razorpay_refund_id) WHERE razorpay_refund_id IS NOT NULL")
    op.execute("ALTER TABLE wallet_transactions DROP CONSTRAINT wallet_transactions_amount_paise_check, ADD COLUMN settlement_channel varchar(20), ADD COLUMN settlement_status varchar(20) NOT NULL DEFAULT 'pending', ADD COLUMN provider_transfer_id varchar(100), ADD COLUMN settled_at timestamptz")
    op.execute("CREATE UNIQUE INDEX uq_wallet_transactions_order_entry ON wallet_transactions(wallet_id, order_id, type) WHERE order_id IS NOT NULL")
    op.execute("CREATE TABLE razorpay_webhook_events (event_id varchar(100) PRIMARY KEY, event_type varchar(80) NOT NULL, payload_hash varchar(64) NOT NULL, status varchar(20) NOT NULL DEFAULT 'processing', error text, processed_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now())")
    op.execute("CREATE TABLE payout_attempts (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), wallet_id uuid NOT NULL REFERENCES wallets(id) ON DELETE CASCADE, amount_paise integer NOT NULL CHECK (amount_paise > 0), status varchar(20) NOT NULL DEFAULT 'pending', attempt_number smallint NOT NULL DEFAULT 1, provider_payout_id varchar(100), error text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now())")
    op.execute("CREATE INDEX ix_payout_attempts_wallet_id ON payout_attempts(wallet_id)")


def downgrade() -> None:
    op.execute("DROP TABLE payout_attempts; DROP TABLE razorpay_webhook_events")
    op.execute("DROP INDEX uq_wallet_transactions_order_entry; ALTER TABLE wallet_transactions DROP COLUMN settled_at, DROP COLUMN provider_transfer_id, DROP COLUMN settlement_status, DROP COLUMN settlement_channel, ADD CONSTRAINT wallet_transactions_amount_paise_check CHECK (amount_paise >= 0)")
    op.execute("DROP INDEX uq_refunds_razorpay_refund_id; DROP INDEX uq_payments_razorpay_payment_id; ALTER TABLE payments DROP COLUMN razorpay_order_id")
    op.execute("DROP INDEX ix_delivery_assignments_status; ALTER TABLE delivery_assignments DROP COLUMN cascade_count, DROP COLUMN timeout_task_id, DROP COLUMN expired_at, DROP COLUMN declined_at, DROP COLUMN status")
    op.execute("DROP INDEX uq_orders_idempotency_key; ALTER TABLE orders DROP COLUMN cancellation_deduction_paise, DROP COLUMN matching_requires_attention, DROP COLUMN razorpay_order_id, DROP COLUMN idempotency_key, DROP COLUMN payment_status")
    op.execute("ALTER TABLE shops DROP COLUMN razorpay_linked_account_id; ALTER TABLE delivery_partner_profiles DROP COLUMN razorpay_linked_account_id")
    op.execute("UPDATE shop_owner_profiles SET kyc_status = 'verified' WHERE kyc_status = 'approved'")