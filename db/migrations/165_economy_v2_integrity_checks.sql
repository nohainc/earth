-- Economy V2 Plan 16: extend EARTH's existing integrity report and add a
-- bounded settlement-day validation surface.

CREATE OR REPLACE FUNCTION earth_integrity_report()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT)
LANGUAGE SQL
AS $$
  SELECT 'buildings_missing_catalog', COUNT(*) FROM buildings b LEFT JOIN building_catalog c ON c.id = b.catalog_id WHERE b.catalog_id IS NOT NULL AND c.id IS NULL
  UNION ALL SELECT 'building_city_missing', COUNT(*) FROM buildings b LEFT JOIN cities c ON c.id = b.city_id WHERE b.city_id IS NOT NULL AND c.id IS NULL
  UNION ALL SELECT 'membership_human_missing', COUNT(*) FROM memberships m LEFT JOIN humans h ON h.id = m.human_id WHERE h.id IS NULL
  UNION ALL SELECT 'membership_city_missing', COUNT(*) FROM memberships m LEFT JOIN cities c ON c.id = m.city_id WHERE m.city_id IS NOT NULL AND c.id IS NULL
  UNION ALL SELECT 'membership_corporation_missing', COUNT(*) FROM memberships m LEFT JOIN corporations c ON c.id = m.corporation_id WHERE m.corporation_id IS NOT NULL AND c.id IS NULL
  UNION ALL SELECT 'account_owner_missing_registry', COUNT(*) FROM account_balances a LEFT JOIN owner_registry o ON o.id = a.owner_id WHERE o.id IS NULL
  UNION ALL SELECT 'building_owner_missing_registry', COUNT(*) FROM buildings b LEFT JOIN owner_registry o ON o.id = b.owner_id WHERE o.id IS NULL
  UNION ALL SELECT 'economic_account_owner_missing', COUNT(*) FROM economic_accounts a LEFT JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.economic_id IS NULL
  UNION ALL SELECT 'duplicate_default_economic_account', COUNT(*) FROM (SELECT owner_economic_id, asset_id FROM economic_accounts WHERE is_default_settlement GROUP BY owner_economic_id, asset_id HAVING COUNT(*) > 1) d
  UNION ALL SELECT 'invalid_asset_account', COUNT(*) FROM economic_accounts a LEFT JOIN economic_assets x ON x.id = a.asset_id WHERE x.id IS NULL
  UNION ALL SELECT 'negative_economic_balance', COUNT(*) FROM economic_accounts WHERE balance < 0
  UNION ALL SELECT 'transaction_without_entries', COUNT(*) FROM economic_transactions t LEFT JOIN economic_entries e ON e.transaction_id = t.id WHERE e.id IS NULL
  UNION ALL SELECT 'orphan_economic_entry', COUNT(*) FROM economic_entries e LEFT JOIN economic_transactions t ON t.id = e.transaction_id WHERE t.id IS NULL
  UNION ALL SELECT 'duplicate_economic_correlation', COUNT(*) FROM (SELECT correlation_id FROM economic_transactions GROUP BY correlation_id HAVING COUNT(*) > 1) d
  UNION ALL SELECT 'unbalanced_economic_transaction', COUNT(*) FROM (
    SELECT e.transaction_id, a.asset_id FROM economic_entries e
    JOIN economic_accounts a ON a.id = e.account_id
    GROUP BY e.transaction_id, a.asset_id HAVING SUM(e.delta) <> 0
  ) d;
$$;

CREATE OR REPLACE FUNCTION earth_validate_settlement_day(
  p_game_day BIGINT,
  p_required_phases TEXT[]
)
RETURNS TABLE(check_name TEXT, invalid_count BIGINT)
LANGUAGE SQL
AS $$
  WITH run AS (
    SELECT shard_count FROM daily_settlement_runs WHERE game_day = $1
  ), required AS (
    SELECT phase, shard::TEXT AS shard
    FROM unnest($2::TEXT[]) phase
    CROSS JOIN run
    CROSS JOIN generate_series(0, run.shard_count - 1) shard
  ), phase_failures AS (
    SELECT r.phase, r.shard
    FROM required r
    LEFT JOIN daily_settlement_phase_runs p
      ON p.game_day = $1 AND p.phase = r.phase AND p.shard = r.shard AND p.status = 'completed'
    WHERE p.game_day IS NULL
  ), unresolved_batches AS (
    SELECT t.id
    FROM economic_transactions t
    LEFT JOIN economic_entries e ON e.transaction_id = t.id
    WHERE t.game_day = $1 AND t.transaction_kind = 'SETTLEMENT_BATCH' AND e.id IS NULL
  ), negative_balances AS (
    SELECT id FROM economic_accounts WHERE balance < 0
  ), duplicate_postings AS (
    SELECT correlation_id FROM economic_transactions GROUP BY correlation_id HAVING COUNT(*) > 1
  ), unbalanced_batches AS (
    SELECT e.transaction_id, a.asset_id
    FROM economic_entries e
    JOIN economic_accounts a ON a.id = e.account_id
    JOIN economic_transactions t ON t.id = e.transaction_id
    WHERE t.game_day = $1 AND t.transaction_kind = 'SETTLEMENT_BATCH'
    GROUP BY e.transaction_id, a.asset_id
    HAVING SUM(e.delta) <> 0
  )
  SELECT 'required_phase_shard_incomplete', (SELECT COUNT(*) FROM phase_failures)
  UNION ALL SELECT 'settlement_run_missing', CASE WHEN EXISTS (SELECT 1 FROM run) THEN 0 ELSE 1 END
  UNION ALL SELECT 'unresolved_settlement_batch', (SELECT COUNT(*) FROM unresolved_batches)
  UNION ALL SELECT 'negative_economic_balance', (SELECT COUNT(*) FROM negative_balances)
  UNION ALL SELECT 'duplicate_settlement_posting', (SELECT COUNT(*) FROM duplicate_postings)
  UNION ALL SELECT 'unbalanced_settlement_batch_asset', (SELECT COUNT(*) FROM unbalanced_batches);
$$;
