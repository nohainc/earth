-- Cities, Corporations & Budgets V2 Plan 16.
-- Revenue is a cash-flow projection, not budget authority.

CREATE TABLE institution_revenue_summary (
  institution_id TEXT NOT NULL REFERENCES institutions(id),
  fiscal_period_id BIGINT NOT NULL REFERENCES fiscal_periods(id),
  game_day BIGINT NOT NULL,
  taxes_received BIGINT NOT NULL DEFAULT 0,
  service_revenue BIGINT NOT NULL DEFAULT 0,
  grants_received BIGINT NOT NULL DEFAULT 0,
  license_income BIGINT NOT NULL DEFAULT 0,
  other_income BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (institution_id, game_day)
);

CREATE OR REPLACE FUNCTION earth_refresh_institution_revenue_summary(p_institution_id TEXT, p_game_day BIGINT)
RETURNS VOID LANGUAGE SQL AS $$
  INSERT INTO institution_revenue_summary (institution_id, fiscal_period_id, game_day, taxes_received, service_revenue, grants_received, license_income, other_income)
  SELECT $1, earth_fiscal_period_for_day($2), $2,
    COALESCE(SUM(e.delta) FILTER (WHERE upper(e.reason_code) LIKE '%TAX%'), 0),
    COALESCE(SUM(e.delta) FILTER (WHERE upper(e.reason_code) LIKE '%SERVICE%'), 0),
    COALESCE(SUM(e.delta) FILTER (WHERE upper(e.reason_code) LIKE '%GRANT%'), 0),
    COALESCE(SUM(e.delta) FILTER (WHERE upper(e.reason_code) LIKE '%LICENSE%'), 0),
    COALESCE(SUM(e.delta) FILTER (WHERE upper(e.reason_code) NOT LIKE '%TAX%' AND upper(e.reason_code) NOT LIKE '%SERVICE%' AND upper(e.reason_code) NOT LIKE '%GRANT%' AND upper(e.reason_code) NOT LIKE '%LICENSE%'), 0)
  FROM economic_entries e
  JOIN economic_accounts a ON a.id = e.account_id
  JOIN owner_registry o ON o.economic_id = a.owner_economic_id
  WHERE o.id = $1 AND e.game_day = $2 AND e.delta > 0
  ON CONFLICT (institution_id, game_day) DO UPDATE SET fiscal_period_id = EXCLUDED.fiscal_period_id, taxes_received = EXCLUDED.taxes_received, service_revenue = EXCLUDED.service_revenue, grants_received = EXCLUDED.grants_received, license_income = EXCLUDED.license_income, other_income = EXCLUDED.other_income, updated_at = CURRENT_TIMESTAMP;
$$;
