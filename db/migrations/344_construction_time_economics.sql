-- Plan 6: construction time is analyzed in the same game-time units used by
-- the world clock. Catalog construction_days remains the authoritative input.
-- 1 game hour = 1 real minute; 1 game day = 24 real minutes.

CREATE OR REPLACE VIEW building_construction_time_model AS
SELECT
  bc.id AS catalog_id,
  bc.building_type,
  bc.tier,
  bc.slot_footprint,
  bc.construction_days AS construction_game_days,
  bc.construction_days * 24 AS construction_game_hours,
  bc.construction_days * 24 AS construction_real_minutes,
  CASE
    WHEN bc.tier <= 2 AND bc.slot_footprint <= 2 THEN 'TINY_BASIC'
    WHEN bc.tier <= 3 THEN 'ORDINARY_PRODUCTION'
    WHEN bc.tier = 4 THEN 'ADVANCED_HIGH_TIER'
    ELSE 'STRATEGIC_T5'
  END AS construction_time_class
FROM building_catalog bc;
