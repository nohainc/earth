-- Migration 099: monitor every shadow owner reference, not only buildings.

CREATE OR REPLACE FUNCTION earth_integrity_report()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT) LANGUAGE SQL AS $$
  SELECT 'buildings_missing_catalog', COUNT(*) FROM buildings b LEFT JOIN building_catalog c ON c.id=b.catalog_id WHERE b.catalog_id IS NOT NULL AND c.id IS NULL
  UNION ALL SELECT 'buildings_missing_owner_registry', COUNT(*) FROM buildings WHERE owner_id IS NOT NULL AND owner_registry_id IS NULL
  UNION ALL SELECT 'businesses_missing_owner_registry', COUNT(*) FROM businesses WHERE owner_id IS NOT NULL AND owner_registry_id IS NULL
  UNION ALL SELECT 'account_balances_missing_owner_registry', COUNT(*) FROM account_balances WHERE owner_id IS NOT NULL AND owner_registry_id IS NULL
  UNION ALL SELECT 'resource_balances_missing_owner_registry', COUNT(*) FROM resource_balances WHERE owner_id IS NOT NULL AND owner_registry_id IS NULL
  UNION ALL SELECT 'resource_ledger_missing_owner_registry', COUNT(*) FROM resource_ledger_entries WHERE owner_id IS NOT NULL AND owner_registry_id IS NULL
  UNION ALL SELECT 'rate_history_missing_owner_registry', COUNT(*) FROM resource_rate_history WHERE owner_id IS NOT NULL AND owner_registry_id IS NULL
  UNION ALL SELECT 'daily_profiles_missing_owner_registry', COUNT(*) FROM daily_settlement_profiles WHERE owner_id IS NOT NULL AND owner_registry_id IS NULL
  UNION ALL SELECT 'daily_profile_runs_missing_owner_registry', COUNT(*) FROM daily_settlement_profile_runs WHERE owner_id IS NOT NULL AND owner_registry_id IS NULL
  UNION ALL SELECT 'technologies_missing_owner_registry', COUNT(*) FROM technologies WHERE owner_id IS NOT NULL AND owner_registry_id IS NULL
  UNION ALL SELECT 'building_city_missing', COUNT(*) FROM buildings b LEFT JOIN cities c ON c.id=b.city_id WHERE b.city_id IS NOT NULL AND c.id IS NULL
  UNION ALL SELECT 'membership_human_missing', COUNT(*) FROM memberships m LEFT JOIN humans h ON h.id=m.human_id WHERE h.id IS NULL
  UNION ALL SELECT 'membership_city_missing', COUNT(*) FROM memberships m LEFT JOIN cities c ON c.id=m.city_id WHERE m.city_id IS NOT NULL AND c.id IS NULL
  UNION ALL SELECT 'membership_corporation_missing', COUNT(*) FROM memberships m LEFT JOIN corporations c ON c.id=m.corporation_id WHERE m.corporation_id IS NOT NULL AND c.id IS NULL;
$$;
