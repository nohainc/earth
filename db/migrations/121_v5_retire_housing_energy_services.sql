-- EARTH ACTIVE MIGRATION: V5 Retire Housing and Energy Services
-- Retires HOUSING and ENERGY service types and need rules in favor of direct
-- resource consumption and automatic residential capacity units.

-- 1. Mark HOUSING and ENERGY service types as RETIRED
UPDATE service_types
   SET status = 'RETIRED'
 WHERE code IN ('HOUSING', 'ENERGY');

-- 2. Mark HOUSING and ENERGY need rules as RETIRED
UPDATE need_rules
   SET status = 'RETIRED'
 WHERE need_code IN ('HOUSING', 'ENERGY')
    OR service_type_code IN ('HOUSING', 'ENERGY');

-- 3. Extend personal_life_maintenance with direct ENERGY resource consumption tracking
ALTER TABLE personal_life_maintenance
  ADD COLUMN IF NOT EXISTS energy_required_units BIGINT NOT NULL DEFAULT 0 CHECK (energy_required_units >= 0),
  ADD COLUMN IF NOT EXISTS energy_consumed_units BIGINT NOT NULL DEFAULT 0 CHECK (energy_consumed_units >= 0),
  ADD COLUMN IF NOT EXISTS energy_shortfall_units BIGINT NOT NULL DEFAULT 0 CHECK (energy_shortfall_units >= 0);
