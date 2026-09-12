-- Economy V2 Plan 5: classify integrity diagnostics and add production-critical
-- checks without creating a second source of truth for domain invariants.

CREATE OR REPLACE FUNCTION earth_critical_integrity_report()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT)
LANGUAGE SQL
AS $$
  WITH transaction_asset_totals AS (
    SELECT e.transaction_id, a.asset_id, SUM(e.delta)::BIGINT AS total_delta
      FROM economic_entries e
      JOIN economic_accounts a ON a.id = e.account_id
     GROUP BY e.transaction_id, a.asset_id
  )
  SELECT 'economic_transaction_unbalanced', COUNT(*)
    FROM transaction_asset_totals WHERE total_delta <> 0
  UNION ALL
  SELECT 'economic_transaction_without_entries', COUNT(*)
    FROM economic_transactions t
   WHERE NOT EXISTS (SELECT 1 FROM economic_entries e WHERE e.transaction_id = t.id)
  UNION ALL
  SELECT 'unauthorized_credit_issuance', COUNT(*)
    FROM economic_entries e
    JOIN economic_accounts a ON a.id = e.account_id
    JOIN owner_registry o ON o.economic_id = a.owner_economic_id
    JOIN economic_transactions t ON t.id = e.transaction_id
   WHERE a.asset_id = 1
     AND ((o.id = 'SYSTEM-MONETARY-AUTHORITY'
           AND (a.account_type <> 7 OR e.delta >= 0
                OR e.reason_code NOT IN ('GENESIS_ISSUANCE', 'PLAYER_STARTING_GRANT', 'MONETARY_STABILIZATION')
                OR t.source_type <> 'monetary_authority'))
       OR (o.id = 'SYSTEM-MONETARY-RETIREMENT'
           AND (a.account_type <> 8 OR e.delta <= 0
                OR e.reason_code <> 'CREDIT_RETIREMENT'
                OR t.source_type <> 'monetary_authority')))
  UNION ALL
  SELECT 'active_house_without_current_human', COUNT(*)
    FROM houses h
    LEFT JOIN humans hu ON hu.id = h.current_human_id AND hu.house_id = h.id AND hu.life_status = 'active'
   WHERE h.status = 'ACTIVE' AND hu.id IS NULL
  UNION ALL
  SELECT 'deceased_current_house_human', COUNT(*)
    FROM houses h JOIN humans hu ON hu.id = h.current_human_id
   WHERE hu.life_status <> 'active'
  UNION ALL
  SELECT 'open_market_order_without_escrow', COUNT(*)
    FROM market_orders
   WHERE status IN ('open', 'partial') AND owner_economic_id IS NOT NULL AND escrow_account_id IS NULL
  UNION ALL
  SELECT 'active_research_without_funding', COUNT(*)
    FROM corporation_research_projects
   WHERE status = 'ACTIVE' AND funding_transaction_id IS NULL
  UNION ALL
  SELECT 'outbox_permanent_lock', COUNT(*)
    FROM event_outbox
   WHERE processed_at IS NULL AND locked_at IS NOT NULL AND locked_at < CURRENT_TIMESTAMP - INTERVAL '30 minutes';
$$;

CREATE OR REPLACE FUNCTION earth_integrity_report_detailed()
RETURNS TABLE(severity TEXT, check_name TEXT, invalid_count BIGINT)
LANGUAGE SQL
AS $$
  SELECT 'critical', check_name, invalid_count FROM earth_integrity_report()
  UNION ALL
  SELECT 'critical', check_name, invalid_count FROM earth_critical_integrity_report()
  UNION ALL
  SELECT 'warning', 'outbox_backlog_pressure', COUNT(*)
    FROM event_outbox WHERE processed_at IS NULL
  UNION ALL
  SELECT 'warning', 'scheduler_stale', COUNT(*)
    FROM world_state
   WHERE id = 'WORLD' AND last_scheduler_at < CURRENT_TIMESTAMP - INTERVAL '10 minutes'
  UNION ALL
  SELECT 'expensive', 'economic_owner_totals_reconciliation', COUNT(*)
    FROM earth_integrity_report()
   WHERE check_name = 'totals_mismatch' AND invalid_count > 0;
$$;
