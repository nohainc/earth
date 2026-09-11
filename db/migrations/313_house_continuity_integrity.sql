-- Death & Continuity V2 Plan 31.
-- Detect identity, succession, ownership, and continuity corruption early.

CREATE OR REPLACE FUNCTION earth_house_continuity_integrity()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT)
LANGUAGE SQL
AS $$
  SELECT 'house_without_exactly_one_current_active_human', COUNT(*)::BIGINT
  FROM (
    SELECT h.id
    FROM houses h LEFT JOIN humans human ON human.house_id = h.id AND human.life_status = 'active'
    WHERE h.status = 'ACTIVE'
    GROUP BY h.id
    HAVING COUNT(human.id) <> 1 OR MAX(h.current_human_id) IS DISTINCT FROM MAX(human.id)
  ) invalid_houses
  UNION ALL
  SELECT 'deceased_human_is_current_house_human', COUNT(*)::BIGINT
  FROM houses h JOIN humans human ON human.id = h.current_human_id
  WHERE human.life_status = 'deceased' OR human.mortality_state = 'DECEASED'
  UNION ALL
  SELECT 'human_without_valid_house', COUNT(*)::BIGINT
  FROM humans human LEFT JOIN houses h ON h.id = human.house_id
  WHERE h.id IS NULL
  UNION ALL
  SELECT 'house_generation_without_succession_event', COUNT(*)::BIGINT
  FROM house_lineage_records lineage
  WHERE lineage.generation > 1
    AND NOT EXISTS (
      SELECT 1 FROM succession_events event
      WHERE event.house_id = lineage.house_id
        AND event.successor_human_id = lineage.human_id
        AND event.status = 'COMPLETED'
    )
  UNION ALL
  SELECT 'deceased_human_active_governance_role', COUNT(*)::BIGINT
  FROM humans human JOIN institutions institution ON institution.administrator_human_id = human.id
  WHERE human.life_status = 'deceased'
  UNION ALL
  SELECT 'deceased_human_active_challenge_authority', COUNT(*)::BIGINT
  FROM proposal_challenge_authorities authority JOIN humans human ON human.id = authority.human_id
  WHERE authority.status = 'active' AND human.life_status = 'deceased'
  UNION ALL
  SELECT 'deceased_human_new_ballot', COUNT(*)::BIGINT
  FROM ballots ballot
  JOIN humans human ON human.id = ballot.human_id
  JOIN life_events death ON death.human_id = human.id AND death.event_type = 'death'
  WHERE human.life_status = 'deceased' AND ballot.created_at > death.created_at
  UNION ALL
  SELECT 'duplicate_house_ballot', COUNT(*)::BIGINT
  FROM (SELECT proposal_id, house_id FROM ballots GROUP BY proposal_id, house_id HAVING COUNT(*) > 1) duplicate_ballots
  UNION ALL
  SELECT 'market_order_invalid_house_owner', COUNT(*)::BIGINT
  FROM market_orders order_row
  LEFT JOIN owner_registry owner ON owner.economic_id = order_row.owner_economic_id
  WHERE order_row.owner_economic_id IS NOT NULL
    AND (owner.economic_id IS NULL OR owner.owner_type NOT IN ('house', 'corporation', 'city', 'system'))
  UNION ALL
  SELECT 'bank_contract_invalid_house_owner', COUNT(*)::BIGINT
  FROM (
    SELECT depositor_economic_id AS owner_economic_id FROM bank_deposits
    UNION ALL SELECT borrower_economic_id FROM bank_loans
  ) contracts
  LEFT JOIN owner_registry owner ON owner.economic_id = contracts.owner_economic_id
  WHERE owner.economic_id IS NULL
    OR owner.owner_type NOT IN ('house', 'corporation', 'city', 'system')
  UNION ALL
  SELECT 'private_building_invalid_house_owner', COUNT(*)::BIGINT
  FROM buildings building
  LEFT JOIN owner_registry owner ON owner.id = building.owner_id
  WHERE building.ownership_class = 'private'
    AND (owner.id IS NULL OR owner.owner_type <> 'house')
  UNION ALL
  SELECT 'deceased_human_equipped_heirloom', COUNT(*)::BIGINT
  FROM house_heirlooms heirloom JOIN humans human ON human.id = heirloom.equipped_by_human_id
  WHERE human.life_status = 'deceased'
  ;
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
  UNION ALL SELECT check_name, invalid_count FROM earth_house_continuity_integrity();
$$;
