-- EARTH ACTIVE MIGRATION: authoritative daily House statement read model

CREATE TABLE IF NOT EXISTS house_daily_statements (
  house_id TEXT NOT NULL REFERENCES houses(id),
  game_day BIGINT NOT NULL,
  opening_assets JSONB NOT NULL DEFAULT '{}'::jsonb,
  closing_assets JSONB NOT NULL DEFAULT '{}'::jsonb,
  production JSONB NOT NULL DEFAULT '{}'::jsonb,
  consumption JSONB NOT NULL DEFAULT '{}'::jsonb,
  market_activity JSONB NOT NULL DEFAULT '{}'::jsonb,
  obligations JSONB NOT NULL DEFAULT '{}'::jsonb,
  exceptions JSONB NOT NULL DEFAULT '{}'::jsonb,
  net_credit_units BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (house_id, game_day)
);

CREATE INDEX IF NOT EXISTS house_daily_statements_day_idx
  ON house_daily_statements (game_day, house_id);

CREATE OR REPLACE FUNCTION earth_refresh_house_daily_statements(p_game_day BIGINT)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE v_count INTEGER;
BEGIN
  WITH owners AS (
    SELECT h.id AS house_id, o.economic_id
      FROM houses h
      JOIN owner_registry o ON o.id = h.id AND o.owner_type = 'HOUSE'
  ),
  daily_delta AS (
    SELECT o.house_id, a.asset_id, SUM(e.delta_units)::BIGINT AS delta_units
      FROM owners o
      JOIN economic_accounts a ON a.owner_economic_id = o.economic_id
      JOIN economic_entries e ON e.account_id = a.id
      JOIN economic_transactions t ON t.id = e.transaction_id AND t.game_day = p_game_day
     GROUP BY o.house_id, a.asset_id
  ),
  balances AS (
    SELECT o.house_id, asset.code,
           COALESCE(SUM(a.balance_units), 0)::BIGINT AS closing_units,
           COALESCE(SUM(a.balance_units), 0)::BIGINT - COALESCE(SUM(d.delta_units), 0)::BIGINT AS opening_units
      FROM owners o
      JOIN economic_accounts a ON a.owner_economic_id = o.economic_id AND a.status = 'ACTIVE'
      JOIN economic_assets asset ON asset.id = a.asset_id
      LEFT JOIN daily_delta d ON d.house_id = o.house_id AND d.asset_id = a.asset_id
     GROUP BY o.house_id, asset.code
  ),
  balance_json AS (
    SELECT house_id,
           jsonb_object_agg(code, opening_units::TEXT ORDER BY code) AS opening_assets,
           jsonb_object_agg(code, closing_units::TEXT ORDER BY code) AS closing_assets
      FROM balances GROUP BY house_id
  ),
  flow_json AS (
    SELECT o.house_id,
           COALESCE(jsonb_object_agg(asset.code, flow.produced::TEXT ORDER BY asset.code) FILTER (WHERE flow.produced > 0), '{}'::jsonb) AS production,
           COALESCE(jsonb_object_agg(asset.code, flow.consumed::TEXT ORDER BY asset.code) FILTER (WHERE flow.consumed > 0), '{}'::jsonb) AS consumption
      FROM owners o
      JOIN economic_accounts a ON a.owner_economic_id = o.economic_id
      JOIN economic_assets asset ON asset.id = a.asset_id
      LEFT JOIN LATERAL (
        SELECT COALESCE(SUM(e.delta_units) FILTER (WHERE t.transaction_kind = 'RESOURCE_PRODUCTION' AND e.delta_units > 0), 0)::BIGINT AS produced,
               COALESCE(SUM(-e.delta_units) FILTER (WHERE t.transaction_kind = 'RESOURCE_CONSUMPTION' AND e.delta_units < 0), 0)::BIGINT AS consumed
          FROM economic_entries e JOIN economic_transactions t ON t.id = e.transaction_id
         WHERE e.account_id = a.id AND t.game_day = p_game_day
      ) flow ON TRUE
     GROUP BY o.house_id
  ),
  market_json AS (
    SELECT owner.house_id,
           jsonb_object_agg(m.symbol, jsonb_build_object(
             'purchases', m.purchases::TEXT, 'sales', m.sales::TEXT,
             'volume', m.volume::TEXT, 'fees', m.fees::TEXT
           ) ORDER BY m.symbol) AS market_activity
      FROM owners owner
      JOIN LATERAL (
        SELECT i.symbol,
               COALESCE(SUM(f.quantity_units) FILTER (WHERE f.buyer_economic_id = owner.economic_id), 0)::BIGINT AS purchases,
               COALESCE(SUM(f.quantity_units) FILTER (WHERE f.seller_economic_id = owner.economic_id), 0)::BIGINT AS sales,
               COALESCE(SUM(f.quantity_units), 0)::BIGINT AS volume,
               COALESCE(SUM(f.buyer_fee_units) FILTER (WHERE f.buyer_economic_id = owner.economic_id), 0)::BIGINT
                 + COALESCE(SUM(f.seller_fee_units) FILTER (WHERE f.seller_economic_id = owner.economic_id), 0)::BIGINT AS fees
          FROM market_fills f JOIN market_batches b ON b.id = f.batch_id JOIN market_instruments i ON i.id = f.instrument_id
         WHERE b.game_day = p_game_day
           AND (f.buyer_economic_id = owner.economic_id OR f.seller_economic_id = owner.economic_id)
         GROUP BY i.symbol
      ) m ON TRUE
     GROUP BY owner.house_id
  ),
  obligation_json AS (
    SELECT owner.house_id,
           jsonb_build_object(
             'taxes', COALESCE(SUM(o.amount_units) FILTER (WHERE o.status IN ('PAID', 'SETTLED')), 0)::TEXT,
             'total', COALESCE(SUM(o.amount_units), 0)::TEXT,
             'count', COUNT(*)::TEXT
           ) AS obligations
      FROM owners owner LEFT JOIN tax_obligations o
        ON o.taxpayer_economic_id = owner.economic_id AND o.game_day = p_game_day
     GROUP BY owner.house_id
  ),
  exception_json AS (
    SELECT h.id AS house_id,
           jsonb_build_object(
             'food_shortfall_units', COALESCE(SUM(m.food_shortfall_units), 0)::TEXT,
             'unfed_humans', COUNT(*) FILTER (WHERE m.status = 'UNFED')::TEXT
           ) AS exceptions
      FROM houses h LEFT JOIN personal_life_maintenance m
        ON m.house_id = h.id AND m.game_day = p_game_day
     GROUP BY h.id
  ),
  rows_to_write AS (
    SELECT b.house_id, p_game_day, b.opening_assets, b.closing_assets,
           COALESCE(f.production, '{}'::jsonb), COALESCE(f.consumption, '{}'::jsonb),
           COALESCE(m.market_activity, '{}'::jsonb), COALESCE(o.obligations, '{}'::jsonb),
           COALESCE(x.exceptions, '{}'::jsonb),
           COALESCE((b.closing_assets ->> 'CREDIT')::BIGINT, 0) - COALESCE((b.opening_assets ->> 'CREDIT')::BIGINT, 0)
      FROM balance_json b
      LEFT JOIN flow_json f USING (house_id)
      LEFT JOIN market_json m USING (house_id)
      LEFT JOIN obligation_json o USING (house_id)
      LEFT JOIN exception_json x USING (house_id)
  )
  INSERT INTO house_daily_statements
    (house_id, game_day, opening_assets, closing_assets, production, consumption, market_activity, obligations, exceptions, net_credit_units)
  SELECT * FROM rows_to_write
  ON CONFLICT (house_id, game_day) DO UPDATE SET
    opening_assets = EXCLUDED.opening_assets, closing_assets = EXCLUDED.closing_assets,
    production = EXCLUDED.production, consumption = EXCLUDED.consumption,
    market_activity = EXCLUDED.market_activity, obligations = EXCLUDED.obligations,
    exceptions = EXCLUDED.exceptions, net_credit_units = EXCLUDED.net_credit_units,
    updated_at = CURRENT_TIMESTAMP;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
