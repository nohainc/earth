-- Market V2 Plan 2: remove the retired Futures schema and make the
-- instrument catalog Spot-only. Historical Futures migrations remain in the
-- migration history, but no current database object supports derivatives.

DROP TABLE IF EXISTS derivative_obligations CASCADE;
DROP TABLE IF EXISTS market_delivery_obligations CASCADE;

DROP INDEX IF EXISTS derivative_obligations_expiry_idx;
DROP INDEX IF EXISTS derivative_obligations_owner_idx;
DROP INDEX IF EXISTS market_delivery_obligations_expiry_idx;
DROP INDEX IF EXISTS market_delivery_obligations_instrument_idx;
DROP INDEX IF EXISTS market_instruments_expiry_idx;

-- Remove retired instrument rows and their Spot-independent read-model data.
DELETE FROM market_fills
 WHERE instrument_id IN (SELECT id FROM market_instruments WHERE instrument_type = 'DELIVERY_FUTURE');
DELETE FROM market_orders
 WHERE instrument_id IN (SELECT id FROM market_instruments WHERE instrument_type = 'DELIVERY_FUTURE');
DELETE FROM market_batch_instruments
 WHERE instrument_id IN (SELECT id FROM market_instruments WHERE instrument_type = 'DELIVERY_FUTURE');
DELETE FROM market_instrument_state
 WHERE instrument_id IN (SELECT id FROM market_instruments WHERE instrument_type = 'DELIVERY_FUTURE');
DELETE FROM market_candles
 WHERE instrument_id IN (SELECT id FROM market_instruments WHERE instrument_type = 'DELIVERY_FUTURE');
DELETE FROM market_instruments WHERE instrument_type = 'DELIVERY_FUTURE';

-- Spot fills always settle immediately, so every fill must identify its
-- Economy V2 posting transaction.
ALTER TABLE market_fills
  ALTER COLUMN economic_transaction_id SET NOT NULL;

DO $$
DECLARE constraint_name TEXT;
BEGIN
  FOR constraint_name IN
    SELECT conname
      FROM pg_constraint
     WHERE conrelid = 'market_instruments'::regclass
       AND pg_get_constraintdef(oid) ILIKE '%DELIVERY_FUTURE%'
  LOOP
    EXECUTE format('ALTER TABLE market_instruments DROP CONSTRAINT %I', constraint_name);
  END LOOP;
END $$;

ALTER TABLE market_instruments DROP COLUMN IF EXISTS expiry_total_game_minute;
ALTER TABLE market_instruments
  ADD CONSTRAINT market_instruments_spot_only_ck CHECK (instrument_type = 'SPOT');

-- Rebuild the shared market integrity function without references to the
-- retired derivative tables. The existing read/integrity entry point remains
-- unchanged for callers.
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
  SELECT 'negative_remaining_quantity', COUNT(*) FROM market_orders
   WHERE quantity_units - filled_units < 0
  UNION ALL
  SELECT 'filled_units_exceed_quantity_units', COUNT(*) FROM market_orders
   WHERE filled_units > quantity_units
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
