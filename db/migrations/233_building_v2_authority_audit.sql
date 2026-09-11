-- Building Economy V2 Plan 1: make authority and overlap risks observable.
--
-- This migration intentionally does not change settlement behavior.  During
-- the staged cutover, it reports where the generic profile path and the
-- building path can both account for the same building economics.

CREATE OR REPLACE FUNCTION earth_building_v2_integrity()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT)
LANGUAGE SQL
AS $$
  SELECT 'active_building_missing_economic_owner', COUNT(*)::BIGINT
  FROM buildings b
  WHERE b.status = 'active'
    AND ((b.ownership_class = 'private' AND b.owner_id IS NULL)
      OR (b.ownership_class = 'civic' AND b.city_id IS NULL))
  UNION ALL
  SELECT 'duplicate_building_journal_day', COUNT(*)::BIGINT
  FROM (
    SELECT building_id, day
    FROM building_settlement_journals
    GROUP BY building_id, day
    HAVING COUNT(*) > 1
  ) duplicates
  UNION ALL
  SELECT 'building_effect_without_journal', COUNT(*)::BIGINT
  FROM settlement_effects e
  JOIN buildings b ON b.id = e.source_id
  LEFT JOIN building_settlement_journals j
    ON j.building_id = b.id AND j.day = e.game_day
  WHERE e.phase = 'building_settlement'
    AND j.id IS NULL
  UNION ALL
  SELECT 'building_journal_without_v2_effect', COUNT(*)::BIGINT
  FROM building_settlement_journals j
  LEFT JOIN settlement_effects e
    ON e.source_id = j.building_id
   AND e.game_day = j.day
   AND e.phase = 'building_settlement'
  WHERE e.id IS NULL
  UNION ALL
  SELECT 'building_effect_missing_source', COUNT(*)::BIGINT
  FROM settlement_effects e
  WHERE e.phase = 'building_settlement'
    AND (e.source_id IS NULL OR NOT EXISTS (
      SELECT 1 FROM buildings b WHERE b.id = e.source_id
    ))
  UNION ALL
  SELECT 'building_profile_overlap_risk', COUNT(*)::BIGINT
  FROM daily_settlement_profiles p
  JOIN buildings b ON (
    (p.owner_kind = 'city' AND b.city_id = p.owner_id AND b.ownership_class = 'civic')
    OR (p.owner_kind <> 'city' AND b.owner_id = p.owner_id AND b.ownership_class = 'private')
  )
  WHERE b.status = 'active'
    AND p.status = 'clean'
    AND (p.material_units <> 0 OR p.components_units <> 0 OR p.energy_units <> 0
      OR p.compute_units <> 0 OR p.food_units <> 0)
$$;

CREATE OR REPLACE FUNCTION earth_integrity_report()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT)
LANGUAGE SQL
AS $$
  SELECT check_name, invalid_count FROM earth_base_integrity_report()
  UNION ALL SELECT check_name, invalid_count FROM earth_market_integrity_report()
  UNION ALL SELECT check_name, invalid_count FROM earth_monetary_supply_integrity()
  UNION ALL SELECT check_name, invalid_count FROM earth_finance_v2_integrity()
  UNION ALL SELECT check_name, invalid_count FROM earth_building_v2_integrity()
$$;
