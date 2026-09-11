-- Market V2 Plan 18: explicit corruption checks for orders, escrow, fills,
-- batches, and fully collateralized delivery obligations.

CREATE OR REPLACE FUNCTION earth_market_integrity_report()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT)
LANGUAGE SQL
AS $$
  SELECT 'open_order_without_escrow', COUNT(*)
    FROM market_orders o
    LEFT JOIN economic_accounts e ON e.id = o.escrow_account_id
   WHERE o.status IN ('open', 'partial')
     AND (e.id IS NULL OR e.account_type <> 6 OR e.status <> 'active')
  UNION ALL
  SELECT 'orphan_market_escrow', COUNT(*)
    FROM economic_accounts e
    LEFT JOIN market_orders o ON o.escrow_account_id = e.id
   WHERE e.account_type = 6
     AND e.legacy_account_id LIKE 'market-order:%'
     AND (o.id IS NULL OR o.status NOT IN ('open', 'partial'))
  UNION ALL
  SELECT 'negative_remaining_quantity', COUNT(*)
    FROM market_orders
   WHERE quantity_units - filled_units < 0
  UNION ALL
  SELECT 'filled_units_exceed_quantity_units', COUNT(*)
    FROM market_orders
   WHERE filled_units > quantity_units
  UNION ALL
  SELECT 'buy_reservation_below_required_maximum', COUNT(*)
    FROM market_orders
   WHERE side = 'buy' AND status IN ('open', 'partial')
     AND reserved_quote_units < (
       ((quantity_units - filled_units) * limit_price_units + 500000) / 1000000
       + ((((quantity_units - filled_units) * limit_price_units + 500000) / 1000000) * buyer_fee_bps + 5000) / 10000
     )
  UNION ALL
  SELECT 'sell_reservation_below_remaining_quantity', COUNT(*)
    FROM market_orders
   WHERE side = 'sell' AND status IN ('open', 'partial')
     AND reserved_base_units < quantity_units - filled_units
  UNION ALL
  SELECT 'market_fill_without_both_orders', COUNT(*)
    FROM market_fills f
    LEFT JOIN market_orders b ON b.id = f.buy_order_id
    LEFT JOIN market_orders s ON s.id = f.sell_order_id
   WHERE b.id IS NULL OR s.id IS NULL
  UNION ALL
  SELECT 'market_fill_not_tied_to_active_batch', COUNT(*)
    FROM market_fills f
    LEFT JOIN market_batch_instruments mbi
      ON mbi.batch_id = f.batch_id AND mbi.instrument_id = f.instrument_id
   WHERE mbi.status IS NULL OR mbi.status NOT IN ('clearing', 'completed')
  UNION ALL
  SELECT 'completed_spot_batch_without_settlement_transaction', COUNT(*)
    FROM market_batch_instruments mbi
    JOIN market_instruments i ON i.id = mbi.instrument_id
   WHERE mbi.status = 'completed' AND i.instrument_type = 'SPOT'
     AND mbi.fill_count > 0 AND mbi.economic_transaction_id IS NULL
  UNION ALL
  SELECT 'position_collateral_mismatch', COUNT(*)
    FROM derivative_obligations d
    JOIN economic_accounts long_escrow ON long_escrow.id = d.long_escrow_account_id
    JOIN economic_accounts short_escrow ON short_escrow.id = d.short_escrow_account_id
   WHERE d.status = 'open'
     AND (long_escrow.balance <> ((d.quantity_units * d.delivery_price_units + 500000) / 1000000)
       OR short_escrow.balance <> d.quantity_units)
  UNION ALL
  SELECT 'expired_derivative_still_open', COUNT(*)
    FROM derivative_obligations d
   WHERE d.status = 'open'
     AND d.expiry_total_game_minute <= (
       SELECT (game_day - 1) * 1440 + game_minute FROM world_state WHERE id = 'WORLD'
     )
  UNION ALL
  SELECT 'settled_obligation_with_nonempty_escrow', COUNT(*)
    FROM derivative_obligations d
    JOIN economic_accounts long_escrow ON long_escrow.id = d.long_escrow_account_id
    JOIN economic_accounts short_escrow ON short_escrow.id = d.short_escrow_account_id
   WHERE d.status = 'settled' AND (long_escrow.balance <> 0 OR short_escrow.balance <> 0)
  UNION ALL
  SELECT 'market_economic_transaction_unbalanced', COUNT(*)
    FROM (
      SELECT t.id, a.asset_id
        FROM economic_transactions t
        JOIN economic_entries e ON e.transaction_id = t.id
        JOIN economic_accounts a ON a.id = e.account_id
       WHERE t.source_type = 'market'
       GROUP BY t.id, a.asset_id
      HAVING SUM(e.delta) <> 0
    ) invalid
$$;

-- Keep the existing integrity subsystem as the public entry point while
-- adding the market report to its result set.
DO $$
BEGIN
  IF to_regprocedure('earth_integrity_report()') IS NOT NULL
     AND to_regprocedure('earth_base_integrity_report()') IS NULL THEN
    ALTER FUNCTION earth_integrity_report() RENAME TO earth_base_integrity_report;
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION earth_integrity_report()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT)
LANGUAGE SQL
AS $$
  SELECT check_name, invalid_count FROM earth_base_integrity_report()
  UNION ALL
  SELECT check_name, invalid_count FROM earth_market_integrity_report()
$$;
