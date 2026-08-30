-- Migration 052: Corporate Patents & Building Licensing Integration
-- Supports 3-tier licensing (Corporate Member, Private Building, City-Wide Civic),
-- transparent prerequisite gating, recurring royalties, and non-punitive expiration.

CREATE TABLE IF NOT EXISTS building_patent_licenses (
  id TEXT PRIMARY KEY,
  patent_id TEXT NOT NULL,
  patent_name TEXT NOT NULL,
  license_type TEXT NOT NULL, -- 'corporate_member', 'private_building', 'city_civic'
  licensee_id TEXT NOT NULL, -- human_id or city_id
  licensor_corporation_id TEXT NOT NULL,
  building_id TEXT REFERENCES buildings(id) ON DELETE SET NULL,
  city_id TEXT,
  is_permanent BOOLEAN NOT NULL DEFAULT FALSE,
  granted_game_day BIGINT NOT NULL,
  expiry_game_day BIGINT NOT NULL,
  royalty_per_day_crd NUMERIC(20,2) NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active', -- 'active', 'renewal_window', 'expired'
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_bld_patent_lic_licensee ON building_patent_licenses (licensee_id, status);
CREATE INDEX IF NOT EXISTS idx_bld_patent_lic_building ON building_patent_licenses (building_id);
CREATE INDEX IF NOT EXISTS idx_bld_patent_lic_city ON building_patent_licenses (city_id, status);

ALTER TABLE buildings
  ADD COLUMN IF NOT EXISTS required_patent_id TEXT,
  ADD COLUMN IF NOT EXISTS patent_license_status TEXT DEFAULT 'unlicensed';
