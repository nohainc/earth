-- EARTH ACTIVE MIGRATION: canonical House automation configuration.
-- Canonical player automation configuration.
-- The legacy policy table remains for historical compatibility, but new
-- player writes and execution use one resolved version per House.

CREATE TABLE IF NOT EXISTS house_automation_versions (
  id TEXT PRIMARY KEY,
  house_id TEXT NOT NULL REFERENCES houses(id),
  version INTEGER NOT NULL CHECK (version > 0),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 1),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'PAUSED', 'SUPERSEDED')),
  -- Legacy storage only. Active V5 automation is defined by explicit rule maps;
  -- presets are not an execution input.
  operating_mode TEXT NOT NULL DEFAULT 'BALANCED' CHECK (operating_mode IN ('CONSERVATIVE', 'BALANCED', 'GROWTH', 'CUSTOM')),
  daily_spend_cap_units BIGINT NOT NULL DEFAULT 0 CHECK (daily_spend_cap_units >= 0),
  reserve_floor_units JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(reserve_floor_units) = 'object'),
  max_input_price_units JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(max_input_price_units) = 'object'),
  min_sale_price_units JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(min_sale_price_units) = 'object'),
  procurement_quantity_units JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(procurement_quantity_units) = 'object'),
  rules_version TEXT NOT NULL,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (house_id, version)
);

CREATE INDEX IF NOT EXISTS house_automation_versions_effective_idx
  ON house_automation_versions (house_id, effective_from_game_day DESC, version DESC)
  WHERE status = 'ACTIVE';

ALTER TABLE policy_execution_log
  ALTER COLUMN policy_id DROP NOT NULL;

ALTER TABLE policy_execution_log
  ADD COLUMN IF NOT EXISTS automation_version_id TEXT REFERENCES house_automation_versions(id);

-- Preserve a usable automation configuration for existing development data by
-- merging the latest effective row of each legacy policy type. No DISTINCT ON
-- by house is used: each type is resolved independently before the merge.
WITH ranked AS (
  SELECT p.*, row_number() OVER (
    PARTITION BY p.house_id, p.policy_type
    ORDER BY p.effective_from_game_day DESC, p.version DESC
  ) AS rn
  FROM house_operating_policies p
  WHERE p.status = 'ACTIVE'
), merged AS (
  SELECT house_id,
         max(effective_from_game_day) AS effective_from_game_day,
         max(version) AS source_version,
         coalesce(max(operating_mode) FILTER (WHERE policy_type = 'OPERATING'), 'BALANCED') AS operating_mode,
         coalesce(max(daily_spend_cap_units) FILTER (WHERE policy_type = 'OPERATING'), 0) AS daily_spend_cap_units,
         coalesce((array_agg(reserve_floor_units) FILTER (WHERE policy_type = 'INVENTORY_RESERVE'))[1], '{}'::jsonb) AS reserve_floor_units,
         coalesce((array_agg(max_input_price_units) FILTER (WHERE policy_type = 'MARKET_STANDING'))[1], '{}'::jsonb) AS max_input_price_units,
         coalesce((array_agg(min_sale_price_units) FILTER (WHERE policy_type = 'MARKET_STANDING'))[1], '{}'::jsonb) AS min_sale_price_units,
         coalesce((array_agg(procurement_quantity_units) FILTER (WHERE policy_type = 'OPERATING'))[1], '{}'::jsonb) AS procurement_quantity_units,
         coalesce(max(rules_version), 'policies-v1') AS rules_version
    FROM ranked
   WHERE rn = 1
   GROUP BY house_id
)
INSERT INTO house_automation_versions (
  id, house_id, version, effective_from_game_day, status, operating_mode,
  daily_spend_cap_units, reserve_floor_units, max_input_price_units,
  min_sale_price_units, procurement_quantity_units, rules_version, correlation_id
)
SELECT 'automation:' || house_id || ':1', house_id, 1, effective_from_game_day,
       'ACTIVE', operating_mode, daily_spend_cap_units, reserve_floor_units,
       max_input_price_units, min_sale_price_units, procurement_quantity_units,
       rules_version, 'automation-backfill:' || house_id
  FROM merged
ON CONFLICT (house_id, version) DO NOTHING;
