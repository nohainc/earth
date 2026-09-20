-- EARTH ACTIVE MIGRATION: explicit House automation resource semantics.
-- Replace the overloaded reserve/procurement names with explicit automation
-- semantics. Existing values are preserved: the old reserve floor becomes both
-- the minimum reserve and the default sell-above threshold; the old purchase
-- quantity becomes the maximum buy quantity.

ALTER TABLE house_automation_versions
  RENAME COLUMN reserve_floor_units TO minimum_reserve_units;

ALTER TABLE house_automation_versions
  RENAME COLUMN procurement_quantity_units TO max_buy_quantity_units;

ALTER TABLE house_automation_versions
  ADD COLUMN IF NOT EXISTS sell_above_units JSONB NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(sell_above_units) = 'object');

ALTER TABLE house_automation_versions
  ADD COLUMN IF NOT EXISTS max_sell_quantity_units JSONB NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(max_sell_quantity_units) = 'object');

UPDATE house_automation_versions
   SET sell_above_units = minimum_reserve_units
 WHERE sell_above_units = '{}'::jsonb;
