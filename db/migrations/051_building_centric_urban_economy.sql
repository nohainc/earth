-- Migration 051: Building-Centric Urban Economy, Slot Footprints, Public Investment Shares, and Civic Dividend Payouts

-- 1. Alter buildings table with self-contained economic and urban zoning attributes
ALTER TABLE buildings ADD COLUMN IF NOT EXISTS slot_footprint INTEGER NOT NULL DEFAULT 1 CHECK (slot_footprint >= 1 AND slot_footprint <= 8);
ALTER TABLE buildings ADD COLUMN IF NOT EXISTS ownership_class TEXT NOT NULL DEFAULT 'private' CHECK (ownership_class IN ('private', 'civic', 'public_investment'));
ALTER TABLE buildings ADD COLUMN IF NOT EXISTS operating_policy TEXT NOT NULL DEFAULT 'balanced' CHECK (operating_policy IN ('balanced', 'high_output', 'eco_reserve', 'overclock'));
ALTER TABLE buildings ADD COLUMN IF NOT EXISTS auto_repair_enabled BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE buildings ADD COLUMN IF NOT EXISTS resource_output_type TEXT DEFAULT 'credits';
ALTER TABLE buildings ADD COLUMN IF NOT EXISTS resource_output_amount NUMERIC(15,2) NOT NULL DEFAULT 0;
ALTER TABLE buildings ADD COLUMN IF NOT EXISTS daily_operating_credits NUMERIC(15,2) NOT NULL DEFAULT 0;

-- Update existing canonical buildings with appropriate slot footprints and ownership classes
UPDATE buildings SET slot_footprint = 6, ownership_class = 'civic', resource_output_type = 'energy', resource_output_amount = 25.0 WHERE id = 'BLD-MUNI-GEO-0084';
UPDATE buildings SET slot_footprint = 4, ownership_class = 'civic', resource_output_type = 'credits', resource_output_amount = 1200.0 WHERE id = 'BLD-MUNI-LOG-0084';
UPDATE buildings SET slot_footprint = 3, ownership_class = 'civic', resource_output_type = 'credits', resource_output_amount = 600.0 WHERE id = 'BLD-MUNI-HOSP-0084';

-- 2. Public Investment Megaproject Shares (Crowdfunding & Pro-Rata Dividends)
CREATE TABLE IF NOT EXISTS building_investment_shares (
  id TEXT PRIMARY KEY,
  building_id TEXT NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
  investor_id TEXT NOT NULL REFERENCES humans(id),
  shares_owned INTEGER NOT NULL CHECK (shares_owned > 0),
  total_shares_issued INTEGER NOT NULL CHECK (total_shares_issued > 0),
  invested_credits NUMERIC(20,2) NOT NULL DEFAULT 0,
  accumulated_dividends_crd NUMERIC(20,2) NOT NULL DEFAULT 0,
  created_game_day BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_building_investor UNIQUE (building_id, investor_id)
);

CREATE INDEX IF NOT EXISTS building_shares_building_idx ON building_investment_shares(building_id);
CREATE INDEX IF NOT EXISTS building_shares_investor_idx ON building_investment_shares(investor_id);

-- 3. Civic Dividend Payout Ledger
CREATE TABLE IF NOT EXISTS civic_dividend_payouts (
  id TEXT PRIMARY KEY,
  city_id TEXT NOT NULL REFERENCES cities(id),
  day BIGINT NOT NULL,
  total_civic_surplus NUMERIC(20,2) NOT NULL DEFAULT 0,
  base_dividend_per_resident NUMERIC(20,2) NOT NULL DEFAULT 0,
  participation_dividend_pool NUMERIC(20,2) NOT NULL DEFAULT 0,
  eligible_residents_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS civic_dividends_city_day_idx ON civic_dividend_payouts(city_id, day);

-- 4. Clean up legacy staff and machine assignments
DROP TABLE IF EXISTS building_staff_assignments CASCADE;
DROP TABLE IF EXISTS municipal_labor_pool CASCADE;
