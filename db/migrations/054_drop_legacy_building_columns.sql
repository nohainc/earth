-- Migration 054: Building Construction Lifecycle & Legacy Column Purge

-- 1. Add construction timeline and progress columns
ALTER TABLE buildings
  ADD COLUMN IF NOT EXISTS construction_started_game_day INTEGER DEFAULT 1,
  ADD COLUMN IF NOT EXISTS construction_complete_game_day INTEGER DEFAULT 1,
  ADD COLUMN IF NOT EXISTS construction_progress NUMERIC(5,2) DEFAULT 100.0;

-- 2. Backfill existing active buildings to 100% completed
UPDATE buildings
SET
  construction_progress = 100.0,
  construction_started_game_day = COALESCE(created_game_day, 1),
  construction_complete_game_day = COALESCE(created_game_day, 1)
WHERE status = 'active' AND (construction_progress IS NULL OR construction_progress = 0);

-- 3. Drop legacy columns that are no longer used by any application code
ALTER TABLE buildings
  DROP COLUMN IF EXISTS ownership_type,
  DROP COLUMN IF EXISTS max_staff_slots,
  DROP COLUMN IF EXISTS base_revenue_crd;
