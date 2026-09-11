"""Rider onboarding fields, Tier 2 batching columns, order drop-off link.

Revision ID: 0003_rider_onboarding_batching
Revises: 0002_integration_hardening
"""
from alembic import op

revision = "0003_rider_onboarding_batching"
down_revision = "0002_integration_hardening"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # --- Delivery partner KYC fields (same shape as the shop-side KYC) ---
    # vehicle_type becomes nullable: the profile is created with only a name,
    # the vehicle is picked later on the KYC step.
    op.execute(
        "ALTER TABLE delivery_partner_profiles "
        "ALTER COLUMN vehicle_type DROP NOT NULL, "
        "ADD COLUMN id_proof_url text, "
        "ADD COLUMN vehicle_number varchar(20), "
        "ADD COLUMN driving_license_url text, "
        "ADD COLUMN bank_account_details jsonb"
    )
    # Existing rows used the pre-Phase-10 vocabulary.
    op.execute(
        "UPDATE delivery_partner_profiles SET vehicle_type = 'bike' "
        "WHERE vehicle_type IN ('motorcycle', 'car')"
    )

    # --- Tier 2 batching columns ---
    op.execute(
        "ALTER TABLE delivery_assignments "
        "ADD COLUMN offer_type varchar(20) NOT NULL DEFAULT 'fresh', "
        "ADD COLUMN detour_meters integer "
        "CONSTRAINT nonneg_detour_meters CHECK (detour_meters IS NULL OR detour_meters >= 0), "
        "ADD COLUMN window_seconds smallint"
    )
    # Backfill the window for offers already on the table.
    op.execute(
        "UPDATE delivery_assignments SET window_seconds = 35 "
        "WHERE window_seconds IS NULL"
    )
    op.execute(
        "CREATE INDEX ix_delivery_assignments_offer_type "
        "ON delivery_assignments(offer_type)"
    )

    # --- Order drop-off link ---
    # Until now the delivery address was used to price the order and then
    # discarded, which left no way to route a delivery or measure a detour.
    op.execute(
        "ALTER TABLE orders ADD COLUMN delivery_address_id uuid "
        "REFERENCES addresses(id) ON DELETE RESTRICT"
    )
    op.execute(
        "CREATE INDEX ix_orders_delivery_address_id "
        "ON orders(delivery_address_id)"
    )

    # --- Stale-online sweep support ---
    # The sweep scans delivery_partner_profiles for is_online = true and joins
    # live_locations by partner; a partial index keeps that scan cheap.
    op.execute(
        "CREATE INDEX ix_delivery_partner_profiles_online "
        "ON delivery_partner_profiles(user_id) WHERE is_online = true"
    )
    # Matching now filters on live_locations.updated_at freshness.
    op.execute(
        "CREATE INDEX ix_live_locations_updated_at ON live_locations(updated_at)"
    )


def downgrade() -> None:
    op.execute("DROP INDEX ix_live_locations_updated_at")
    op.execute("DROP INDEX ix_delivery_partner_profiles_online")
    op.execute("DROP INDEX ix_orders_delivery_address_id")
    op.execute("ALTER TABLE orders DROP COLUMN delivery_address_id")
    op.execute("DROP INDEX ix_delivery_assignments_offer_type")
    op.execute(
        "ALTER TABLE delivery_assignments "
        "DROP COLUMN window_seconds, "
        "DROP COLUMN detour_meters, "
        "DROP COLUMN offer_type"
    )
    op.execute(
        "UPDATE delivery_partner_profiles SET vehicle_type = 'motorcycle' "
        "WHERE vehicle_type IN ('bike', 'scooter')"
    )
    op.execute(
        "ALTER TABLE delivery_partner_profiles "
        "DROP COLUMN bank_account_details, "
        "DROP COLUMN driving_license_url, "
        "DROP COLUMN vehicle_number, "
        "DROP COLUMN id_proof_url"
    )
    # Backfill before restoring NOT NULL so the constraint can be satisfied.
    op.execute(
        "UPDATE delivery_partner_profiles SET vehicle_type = 'motorcycle' "
        "WHERE vehicle_type IS NULL"
    )
    op.execute(
        "ALTER TABLE delivery_partner_profiles "
        "ALTER COLUMN vehicle_type SET NOT NULL"
    )
