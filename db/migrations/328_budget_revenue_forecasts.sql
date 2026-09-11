-- Cities, Corporations & Budgets V2 Plan 17.
-- Forecasts advise governance; budget lines remain the spending authority.

CREATE TABLE institution_fiscal_budget_forecasts (
  institution_id TEXT NOT NULL REFERENCES institutions(id),
  fiscal_period_id BIGINT NOT NULL REFERENCES fiscal_periods(id),
  opening_cash_units BIGINT NOT NULL DEFAULT 0,
  forecast_revenue_units BIGINT NOT NULL DEFAULT 0 CHECK (forecast_revenue_units >= 0),
  minimum_closing_reserve_units BIGINT NOT NULL DEFAULT 0 CHECK (minimum_closing_reserve_units >= 0),
  recommended_spending_ceiling_units BIGINT NOT NULL DEFAULT 0 CHECK (recommended_spending_ceiling_units >= 0),
  authorized_spending_units BIGINT NOT NULL DEFAULT 0 CHECK (authorized_spending_units >= 0),
  actual_revenue_units BIGINT NOT NULL DEFAULT 0 CHECK (actual_revenue_units >= 0),
  actual_spending_units BIGINT NOT NULL DEFAULT 0 CHECK (actual_spending_units >= 0),
  planned_deficit_units BIGINT NOT NULL DEFAULT 0,
  fiscal_surplus_deficit_units BIGINT NOT NULL DEFAULT 0,
  rule_version TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (institution_id, fiscal_period_id)
);

CREATE OR REPLACE FUNCTION earth_set_budget_revenue_forecast(
  p_institution_id TEXT,
  p_fiscal_period_id BIGINT,
  p_forecast_revenue_units BIGINT,
  p_minimum_closing_reserve_units BIGINT,
  p_authorized_spending_units BIGINT,
  p_rule_version TEXT
)
RETURNS TABLE (
  institution_id TEXT,
  fiscal_period_id BIGINT,
  recommended_spending_ceiling_units BIGINT,
  authorized_spending_units BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_owner_economic_id BIGINT;
  v_opening_cash_units BIGINT;
  v_recommended_units BIGINT;
BEGIN
  IF p_forecast_revenue_units < 0 OR p_minimum_closing_reserve_units < 0 OR p_authorized_spending_units < 0 THEN
    RAISE EXCEPTION 'Budget forecast values cannot be negative';
  END IF;
  IF NULLIF(p_rule_version, '') IS NULL THEN
    RAISE EXCEPTION 'Budget forecast rule version is required';
  END IF;

  SELECT o.economic_id INTO v_owner_economic_id
    FROM institutions i
    JOIN owner_registry o ON o.id = i.id
   WHERE i.id = p_institution_id AND o.status = 'active';
  IF v_owner_economic_id IS NULL THEN
    RAISE EXCEPTION 'Institution % has no active economic owner', p_institution_id;
  END IF;

  SELECT COALESCE(SUM(a.balance), 0) INTO v_opening_cash_units
    FROM economic_accounts a
   WHERE a.owner_economic_id = v_owner_economic_id
     AND a.asset_id = 1
     AND a.account_type = 3
     AND a.is_default_settlement
     AND a.status = 'active';

  v_recommended_units := GREATEST(0, v_opening_cash_units + p_forecast_revenue_units - p_minimum_closing_reserve_units);

  INSERT INTO institution_fiscal_budget_forecasts (
    institution_id, fiscal_period_id, opening_cash_units, forecast_revenue_units,
    minimum_closing_reserve_units, recommended_spending_ceiling_units,
    authorized_spending_units, planned_deficit_units, rule_version
  ) VALUES (
    p_institution_id, p_fiscal_period_id, v_opening_cash_units, p_forecast_revenue_units,
    p_minimum_closing_reserve_units, v_recommended_units,
    p_authorized_spending_units, p_authorized_spending_units - p_forecast_revenue_units, p_rule_version
  )
  ON CONFLICT (institution_id, fiscal_period_id) DO UPDATE SET
    opening_cash_units = EXCLUDED.opening_cash_units,
    forecast_revenue_units = EXCLUDED.forecast_revenue_units,
    minimum_closing_reserve_units = EXCLUDED.minimum_closing_reserve_units,
    recommended_spending_ceiling_units = EXCLUDED.recommended_spending_ceiling_units,
    authorized_spending_units = EXCLUDED.authorized_spending_units,
    rule_version = EXCLUDED.rule_version,
    updated_at = CURRENT_TIMESTAMP;

  RETURN QUERY SELECT p_institution_id, p_fiscal_period_id, v_recommended_units, p_authorized_spending_units;
END;
$$;

CREATE OR REPLACE FUNCTION earth_refresh_fiscal_budget_forecast(p_institution_id TEXT, p_fiscal_period_id BIGINT)
RETURNS TABLE (institution_id TEXT, fiscal_period_id BIGINT, actual_revenue_units BIGINT, actual_spending_units BIGINT, fiscal_surplus_deficit_units BIGINT)
LANGUAGE plpgsql AS $$
DECLARE v_actual_revenue_units BIGINT; v_actual_spending_units BIGINT;
BEGIN
  SELECT COALESCE(SUM(r.taxes_received + r.service_revenue + r.grants_received + r.license_income + r.other_income), 0) INTO v_actual_revenue_units FROM institution_revenue_summary r WHERE r.institution_id = p_institution_id AND r.fiscal_period_id = p_fiscal_period_id;
  SELECT COALESCE(SUM(l.spent_units), 0) INTO v_actual_spending_units FROM institution_budget_lines l WHERE l.institution_id = p_institution_id AND l.fiscal_period_id = p_fiscal_period_id;
  UPDATE institution_fiscal_budget_forecasts f SET actual_revenue_units = v_actual_revenue_units, actual_spending_units = v_actual_spending_units, fiscal_surplus_deficit_units = v_actual_revenue_units - v_actual_spending_units, updated_at = CURRENT_TIMESTAMP WHERE f.institution_id = p_institution_id AND f.fiscal_period_id = p_fiscal_period_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'No fiscal budget forecast exists for institution % and period %', p_institution_id, p_fiscal_period_id; END IF;
  RETURN QUERY SELECT p_institution_id, p_fiscal_period_id, v_actual_revenue_units, v_actual_spending_units, v_actual_revenue_units - v_actual_spending_units;
END; $$;

COMMENT ON TABLE institution_fiscal_budget_forecasts IS
  'Advisory fiscal-period revenue and spending forecast; deficits are reporting values and authorization remains on institution_budget_lines.';
