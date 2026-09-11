-- Technology & Research V2 Plan 39: integrity checks for the unified IP/R&D model.

CREATE OR REPLACE FUNCTION earth_ip_rd_integrity()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT)
LANGUAGE SQL
AS $$
  SELECT 'completed_research_missing_effect'::TEXT, COUNT(*)::BIGINT
  FROM corporation_research_projects p
  WHERE p.status = 'COMPLETED' AND p.completed_game_day IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM corporation_technology_access a
      WHERE p.target_type = 'TECHNOLOGY' AND a.corporation_economic_id = p.corporation_economic_id
        AND a.technology_id = p.target_id AND a.access_source = 'RESEARCHED'
        AND a.source_id = p.id AND a.status = 'ACTIVE'
        AND a.effective_from_game_day = p.completed_game_day + 1
    )
    AND NOT EXISTS (
      SELECT 1 FROM corporation_building_unlocks u
      JOIN owner_registry o ON o.id = u.corporation_id
      WHERE p.target_type = 'BUILDING_BLUEPRINT' AND o.economic_id = p.corporation_economic_id
        AND u.catalog_id = p.target_id AND u.status = 'unlocked'
        AND u.unlocked_game_day = p.completed_game_day + 1
    )
  UNION ALL
  SELECT 'active_license_without_valid_patent', COUNT(*)::BIGINT
  FROM technology_license_contracts c
  LEFT JOIN technology_patents p ON p.id = c.patent_id
  CROSS JOIN world_state w
  WHERE c.status = 'ACTIVE'
    AND (p.id IS NULL OR p.status <> 'ACTIVE' OR p.exclusive_through_game_day < w.game_day)
  UNION ALL
  SELECT 'paid_through_license_without_payment', COUNT(*)::BIGINT
  FROM technology_license_contracts c
  WHERE c.paid_through_game_day >= c.effective_from_game_day
    AND NOT EXISTS (SELECT 1 FROM technology_license_payments p
      WHERE p.contract_id = c.id AND p.game_day = c.paid_through_game_day)
  UNION ALL
  SELECT 'licensed_access_after_contract_expiry', COUNT(*)::BIGINT
  FROM corporation_technology_access a
  LEFT JOIN technology_license_contracts c ON c.id = a.source_id
  WHERE a.access_source = 'LICENSED' AND a.status = 'ACTIVE'
    AND (c.id IS NULL OR c.status IN ('EXPIRED','TERMINATED')
      OR (c.effective_to_game_day IS NOT NULL AND c.effective_to_game_day < a.effective_from_game_day))
  UNION ALL
  SELECT 'multiple_exclusive_active_patents', CASE WHEN EXISTS (
    SELECT 1 FROM technology_patents WHERE status = 'ACTIVE'
    GROUP BY technology_id HAVING COUNT(*) > 1
  ) THEN 1 ELSE 0 END
  UNION ALL
  SELECT 'patent_for_non_patentable_technology', COUNT(*)::BIGINT
  FROM technology_patents p JOIN technology_catalog t ON t.id = p.technology_id
  WHERE t.patentable = FALSE
  UNION ALL
  SELECT 'patent_owner_not_corporation', COUNT(*)::BIGINT
  FROM technology_patents p LEFT JOIN owner_registry o ON o.economic_id = p.owner_economic_id
  WHERE o.economic_id IS NULL OR o.owner_type <> 'corporation'
  UNION ALL
  SELECT 'technology_modifier_cache_source_mismatch', COUNT(*)::BIGINT
  FROM corporation_technology_modifier_cache cache
  WHERE cache.source_count <> (SELECT COUNT(DISTINCT a.technology_id)::INTEGER
    FROM corporation_technology_access a JOIN technology_catalog t ON t.id = a.technology_id
    WHERE a.corporation_economic_id = cache.corporation_economic_id AND a.status = 'ACTIVE'
      AND a.effective_from_game_day <= cache.game_day
      AND (a.effective_to_game_day IS NULL OR a.effective_to_game_day >= cache.game_day)
      AND t.status = 'ACTIVE' AND t.effective_from_game_day <= cache.game_day
      AND (t.effective_to_game_day IS NULL OR t.effective_to_game_day >= cache.game_day))
  UNION ALL
  SELECT 'building_modifier_without_corporation_access', COUNT(*)::BIGINT
  FROM building_settlement_plans b JOIN corporation_technology_modifier_cache cache
    ON cache.corporation_economic_id = b.owner_economic_id AND cache.game_day = b.game_day
  WHERE (cache.production_output_bps <> 0 OR cache.material_input_bps <> 0
      OR cache.energy_input_bps <> 0 OR cache.wear_bps <> 0
      OR cache.repair_efficiency_bps <> 0 OR cache.service_capacity_bps <> 0)
    AND NOT EXISTS (SELECT 1 FROM corporation_technology_access a
      WHERE a.corporation_economic_id = b.owner_economic_id AND a.status = 'ACTIVE'
        AND a.effective_from_game_day <= b.game_day
        AND (a.effective_to_game_day IS NULL OR a.effective_to_game_day >= b.game_day));
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
  UNION ALL SELECT check_name, invalid_count FROM earth_building_profile_overlap_integrity()
  UNION ALL SELECT check_name, invalid_count FROM earth_ip_rd_integrity()
$$;
