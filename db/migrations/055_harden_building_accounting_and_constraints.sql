-- Migration 055: Building Accounting Model Hardening, Settlement Journals, and Referential Integrity

-- 1. Ensure zero-balance market clearing account exists
INSERT INTO account_balances (account_id, owner_id, currency, balance, created_at, updated_at)
VALUES
  ('account-market-clearing', 'SYSTEM', 'CREDIT', 0.00, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT (account_id) DO NOTHING;

-- 2. Ensure operations accounts exist for all existing cities
INSERT INTO account_balances (account_id, owner_id, currency, balance, created_at, updated_at)
SELECT 'account-city-operations-' || id, id, 'CREDIT', 0.00, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
FROM cities
ON CONFLICT (account_id) DO NOTHING;

-- 3. Add strict check constraints on buildings construction fields
ALTER TABLE buildings
  DROP CONSTRAINT IF EXISTS chk_building_construction_progress,
  DROP CONSTRAINT IF EXISTS chk_building_construction_days;

ALTER TABLE buildings
  ADD CONSTRAINT chk_building_construction_progress CHECK (construction_progress >= 0.0 AND construction_progress <= 100.0),
  ADD CONSTRAINT chk_building_construction_days CHECK (construction_complete_game_day >= construction_started_game_day);

-- 4. Add referential integrity and type constraints on building_patent_licenses
ALTER TABLE building_patent_licenses
  DROP CONSTRAINT IF EXISTS fk_patent_license_patent,
  DROP CONSTRAINT IF EXISTS fk_patent_license_city,
  DROP CONSTRAINT IF EXISTS chk_patent_license_type,
  DROP CONSTRAINT IF EXISTS chk_patent_license_status;

ALTER TABLE building_patent_licenses
  ADD CONSTRAINT fk_patent_license_patent FOREIGN KEY (patent_id) REFERENCES patents(id) ON DELETE CASCADE,
  ADD CONSTRAINT fk_patent_license_city FOREIGN KEY (city_id) REFERENCES cities(id) ON DELETE SET NULL,
  ADD CONSTRAINT chk_patent_license_type CHECK (license_type IN ('corporate_member', 'private_building', 'city_civic')),
  ADD CONSTRAINT chk_patent_license_status CHECK (status IN ('active', 'renewal_window', 'expired'));

-- 5. Daily Building Settlement Journals table for exact accounting and dividend auditability
CREATE TABLE IF NOT EXISTS building_settlement_journals (
  id TEXT PRIMARY KEY,
  building_id TEXT NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
  city_id TEXT NOT NULL REFERENCES cities(id) ON DELETE CASCADE,
  day INTEGER NOT NULL,
  ownership_class TEXT NOT NULL,
  gross_revenue_crd NUMERIC(20,2) NOT NULL DEFAULT 0,
  operating_costs_crd NUMERIC(20,2) NOT NULL DEFAULT 0,
  net_surplus_crd NUMERIC(20,2) NOT NULL DEFAULT 0,
  condition_start NUMERIC(5,2) NOT NULL,
  condition_end NUMERIC(5,2) NOT NULL,
  auto_repaired BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_bld_settle_city_day ON building_settlement_journals (city_id, day);
CREATE INDEX IF NOT EXISTS idx_bld_settle_building_day ON building_settlement_journals (building_id, day);
