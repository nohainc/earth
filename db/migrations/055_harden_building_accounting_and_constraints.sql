-- Migration 055: Building Accounting Model Hardening, Operations Accounts, and Strict Constraints

-- 1. Ensure system accounting accounts exist for market settlement and city operations
INSERT INTO account_balances (account_id, owner_id, currency, balance, created_at, updated_at)
VALUES
  ('account-market-settlement', 'SYSTEM', 'CREDIT', 100000000.00, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('account-city-operations-CITY-0084', 'CITY-0084', 'CREDIT', 0.00, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT (account_id) DO NOTHING;

-- 2. Add strict check constraints on buildings construction fields
ALTER TABLE buildings
  DROP CONSTRAINT IF EXISTS chk_building_construction_progress,
  DROP CONSTRAINT IF EXISTS chk_building_construction_days;

ALTER TABLE buildings
  ADD CONSTRAINT chk_building_construction_progress CHECK (construction_progress >= 0.0 AND construction_progress <= 100.0),
  ADD CONSTRAINT chk_building_construction_days CHECK (construction_complete_game_day >= construction_started_game_day);

-- 3. Add foreign key constraints on building_patent_licenses for referential integrity
ALTER TABLE building_patent_licenses
  DROP CONSTRAINT IF EXISTS fk_patent_license_patent,
  DROP CONSTRAINT IF EXISTS fk_patent_license_building;

ALTER TABLE building_patent_licenses
  ADD CONSTRAINT fk_patent_license_patent FOREIGN KEY (patent_id) REFERENCES technology_patents(id) ON DELETE CASCADE;
