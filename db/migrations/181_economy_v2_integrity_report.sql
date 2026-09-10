-- Economy V2 Plan 39: extend the existing integrity report without creating a
-- second diagnostic subsystem.

CREATE OR REPLACE FUNCTION earth_integrity_report()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT)
LANGUAGE SQL
AS $$
  WITH active_owner_assets AS (
    SELECT o.economic_id, a.id AS asset_id
    FROM owner_registry o CROSS JOIN economic_assets a
    WHERE o.status = 'active'
  ),
  expected_totals AS (
    SELECT a.owner_economic_id,
      COALESCE(SUM(e.delta) FILTER (WHERE x.code = 'CREDIT' AND e.delta > 0), 0)::BIGINT AS credit_received,
      COALESCE(SUM(-e.delta) FILTER (WHERE x.code = 'CREDIT' AND e.delta < 0), 0)::BIGINT AS credit_spent,
      COALESCE(SUM(e.delta) FILTER (WHERE x.code = 'MATERIAL' AND e.delta > 0), 0)::BIGINT AS material_received,
      COALESCE(SUM(-e.delta) FILTER (WHERE x.code = 'MATERIAL' AND e.delta < 0), 0)::BIGINT AS material_spent,
      COALESCE(SUM(e.delta) FILTER (WHERE x.code = 'COMPONENTS' AND e.delta > 0), 0)::BIGINT AS components_received,
      COALESCE(SUM(-e.delta) FILTER (WHERE x.code = 'COMPONENTS' AND e.delta < 0), 0)::BIGINT AS components_spent,
      COALESCE(SUM(e.delta) FILTER (WHERE x.code = 'ENERGY' AND e.delta > 0), 0)::BIGINT AS energy_received,
      COALESCE(SUM(-e.delta) FILTER (WHERE x.code = 'ENERGY' AND e.delta < 0), 0)::BIGINT AS energy_spent,
      COALESCE(SUM(e.delta) FILTER (WHERE x.code = 'COMPUTE' AND e.delta > 0), 0)::BIGINT AS compute_received,
      COALESCE(SUM(-e.delta) FILTER (WHERE x.code = 'COMPUTE' AND e.delta < 0), 0)::BIGINT AS compute_spent,
      COALESCE(SUM(e.delta) FILTER (WHERE x.code = 'FOOD' AND e.delta > 0), 0)::BIGINT AS food_received,
      COALESCE(SUM(-e.delta) FILTER (WHERE x.code = 'FOOD' AND e.delta < 0), 0)::BIGINT AS food_spent
    FROM economic_entries e
    JOIN economic_accounts a ON a.id = e.account_id
    JOIN economic_assets x ON x.id = a.asset_id
    GROUP BY a.owner_economic_id
  ),
  totals_mismatch AS (
    SELECT t.owner_economic_id
    FROM economic_owner_totals t
    FULL JOIN expected_totals e USING (owner_economic_id)
    WHERE ROW(t.credit_received, t.credit_spent, t.material_received, t.material_spent,
              t.components_received, t.components_spent, t.energy_received, t.energy_spent,
              t.compute_received, t.compute_spent, t.food_received, t.food_spent)
       IS DISTINCT FROM
          ROW(COALESCE(e.credit_received, 0), COALESCE(e.credit_spent, 0),
              COALESCE(e.material_received, 0), COALESCE(e.material_spent, 0),
              COALESCE(e.components_received, 0), COALESCE(e.components_spent, 0),
              COALESCE(e.energy_received, 0), COALESCE(e.energy_spent, 0),
              COALESCE(e.compute_received, 0), COALESCE(e.compute_spent, 0),
              COALESCE(e.food_received, 0), COALESCE(e.food_spent, 0))
  ),
  balance_mismatch AS (
    SELECT a.id
    FROM economic_accounts a
    LEFT JOIN (
      SELECT economic_account_id, SUM(legacy_balance_units)::BIGINT AS opening_units
      FROM economic_account_migrations GROUP BY economic_account_id
    ) opening ON opening.economic_account_id = a.id
    LEFT JOIN (
      SELECT account_id, SUM(delta)::BIGINT AS ledger_units
      FROM economic_entries GROUP BY account_id
    ) ledger ON ledger.account_id = a.id
    WHERE a.balance <> COALESCE(opening.opening_units, 0) + COALESCE(ledger.ledger_units, 0)
  )
  SELECT 'buildings_missing_catalog', COUNT(*) FROM buildings b LEFT JOIN building_catalog c ON c.id = b.catalog_id WHERE b.catalog_id IS NOT NULL AND c.id IS NULL
  UNION ALL SELECT 'building_city_missing', COUNT(*) FROM buildings b LEFT JOIN cities c ON c.id = b.city_id WHERE b.city_id IS NOT NULL AND c.id IS NULL
  UNION ALL SELECT 'membership_human_missing', COUNT(*) FROM memberships m LEFT JOIN humans h ON h.id = m.human_id WHERE h.id IS NULL
  UNION ALL SELECT 'membership_city_missing', COUNT(*) FROM memberships m LEFT JOIN cities c ON c.id = m.city_id WHERE m.city_id IS NOT NULL AND c.id IS NULL
  UNION ALL SELECT 'membership_corporation_missing', COUNT(*) FROM memberships m LEFT JOIN corporations c ON c.id = m.corporation_id WHERE m.corporation_id IS NOT NULL AND c.id IS NULL
  UNION ALL SELECT 'account_owner_missing_registry', COUNT(*) FROM account_balances a LEFT JOIN owner_registry o ON o.id = a.owner_id WHERE o.id IS NULL
  UNION ALL SELECT 'building_owner_missing_registry', COUNT(*) FROM buildings b LEFT JOIN owner_registry o ON o.id = b.owner_id WHERE o.id IS NULL
  UNION ALL SELECT 'economic_account_owner_missing', COUNT(*) FROM economic_accounts a LEFT JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.economic_id IS NULL
  UNION ALL SELECT 'missing_default_economic_account', COUNT(*) FROM active_owner_assets x LEFT JOIN economic_accounts a ON a.owner_economic_id = x.economic_id AND a.asset_id = x.asset_id AND a.is_default_settlement AND a.status = 'active' WHERE a.id IS NULL
  UNION ALL SELECT 'multiple_active_default_economic_account', COUNT(*) FROM (SELECT owner_economic_id, asset_id FROM economic_accounts WHERE is_default_settlement AND status = 'active' GROUP BY owner_economic_id, asset_id HAVING COUNT(*) > 1) d
  UNION ALL SELECT 'invalid_asset_account', COUNT(*) FROM economic_accounts a LEFT JOIN economic_assets x ON x.id = a.asset_id WHERE x.id IS NULL
  UNION ALL SELECT 'account_asset_mismatch', COUNT(*) FROM economic_accounts WHERE (account_type IN (1, 3, 4, 5) AND asset_id <> 1) OR (account_type = 2 AND asset_id = 1) OR (account_type = 10 AND asset_id <> 1)
  UNION ALL SELECT 'negative_economic_balance', COUNT(*) FROM economic_accounts a LEFT JOIN economic_account_types t ON t.id = a.account_type WHERE a.balance < 0 AND COALESCE(t.allows_negative, FALSE) = FALSE
  UNION ALL SELECT 'wrong_account_shard', COUNT(*) FROM economic_accounts WHERE account_type = 9 AND settlement_shard IS NOT NULL AND settlement_shard <> earth_settlement_shard(owner_economic_id, 64)
  UNION ALL SELECT 'wrong_profile_shard', COUNT(*) FROM daily_settlement_profiles WHERE shard <> earth_settlement_shard(owner_economic_id, 64)
  UNION ALL SELECT 'wrong_effect_shard', COUNT(*) FROM settlement_effects e JOIN economic_accounts a ON a.id = e.account_id WHERE a.account_type <> 9 AND e.shard <> earth_settlement_shard(e.owner_economic_id, 64)
  UNION ALL SELECT 'transaction_without_entries', COUNT(*) FROM economic_transactions t LEFT JOIN economic_entries e ON e.transaction_id = t.id WHERE e.id IS NULL
  UNION ALL SELECT 'orphan_economic_entry', COUNT(*) FROM economic_entries e LEFT JOIN economic_transactions t ON t.id = e.transaction_id WHERE t.id IS NULL
  UNION ALL SELECT 'duplicate_economic_correlation', COUNT(*) FROM (SELECT correlation_id FROM economic_transactions GROUP BY correlation_id HAVING COUNT(*) > 1) d
  UNION ALL SELECT 'unbalanced_economic_transaction', COUNT(*) FROM (SELECT e.transaction_id, a.asset_id FROM economic_entries e JOIN economic_accounts a ON a.id = e.account_id GROUP BY e.transaction_id, a.asset_id HAVING SUM(e.delta) <> 0) d
  UNION ALL SELECT 'balance_vs_ledger_mismatch', COUNT(*) FROM balance_mismatch
  UNION ALL SELECT 'stale_dirty_profile', COUNT(*) FROM daily_settlement_profiles WHERE status = 'dirty' AND updated_at < CURRENT_TIMESTAMP - INTERVAL '15 minutes'
  UNION ALL SELECT 'stale_clean_profile', COUNT(*) FROM daily_settlement_profiles p CROSS JOIN world_state w WHERE p.status = 'clean' AND p.effective_from_game_day < w.game_day
  UNION ALL SELECT 'incomplete_entry_partition_provisioning', CASE WHEN COALESCE((SELECT MAX(to_game_day) FROM economic_entry_partitions), 0) < (SELECT game_day FROM world_state LIMIT 1) + 1000 THEN 1 ELSE 0 END
  UNION ALL SELECT 'entries_left_in_default_partition', COUNT(*) FROM economic_entries_default WHERE game_day < (SELECT game_day FROM world_state LIMIT 1) + 1000
  UNION ALL SELECT 'completed_day_effects_remaining', COUNT(*) FROM settlement_effects e WHERE e.game_day <= COALESCE((SELECT MAX(game_day) FROM daily_settlement_runs WHERE status = 'completed'), -1)
  UNION ALL SELECT 'economic_owner_totals_mismatch', COUNT(*) FROM totals_mismatch
  UNION ALL SELECT 'source_sink_conservation_failure', COUNT(*) FROM (SELECT e.transaction_id, a.asset_id FROM economic_entries e JOIN economic_accounts a ON a.id = e.account_id WHERE a.account_type IN (7, 8) GROUP BY e.transaction_id, a.asset_id HAVING SUM(e.delta) <> 0) d
  UNION ALL SELECT 'v2_legacy_reconciliation_difference', COUNT(*) FROM economy_shadow_reconciliations WHERE difference_kind <> 'none'
  UNION ALL SELECT 'v2_legacy_reconciliation_unexplained_run', COUNT(*) FROM economy_shadow_runs WHERE unexplained_difference
$$;

