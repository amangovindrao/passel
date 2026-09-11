"""Record why a KYC submission was rejected.

Revision ID: 0004_kyc_review
Revises: 0003_rider_onboarding_batching

Both profile tables could reach kyc_status='rejected' with no way to say why,
which left the apps showing a generic "we could not verify you" and the person
with nothing to act on.
"""
from alembic import op

revision = "0004_kyc_review"
down_revision = "0003_rider_onboarding_batching"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        "ALTER TABLE delivery_partner_profiles "
        "ADD COLUMN kyc_rejection_reason text, "
        "ADD COLUMN kyc_reviewed_at timestamptz"
    )
    op.execute(
        "ALTER TABLE shop_owner_profiles "
        "ADD COLUMN kyc_rejection_reason text, "
        "ADD COLUMN kyc_reviewed_at timestamptz"
    )
    # Reviewers work off the pending queue, so make that lookup cheap.
    op.execute(
        "CREATE INDEX ix_delivery_partner_profiles_kyc_status "
        "ON delivery_partner_profiles(kyc_status)"
    )
    op.execute(
        "CREATE INDEX ix_shop_owner_profiles_kyc_status "
        "ON shop_owner_profiles(kyc_status)"
    )


def downgrade() -> None:
    op.execute("DROP INDEX ix_shop_owner_profiles_kyc_status")
    op.execute("DROP INDEX ix_delivery_partner_profiles_kyc_status")
    op.execute(
        "ALTER TABLE shop_owner_profiles "
        "DROP COLUMN kyc_reviewed_at, "
        "DROP COLUMN kyc_rejection_reason"
    )
    op.execute(
        "ALTER TABLE delivery_partner_profiles "
        "DROP COLUMN kyc_reviewed_at, "
        "DROP COLUMN kyc_rejection_reason"
    )
