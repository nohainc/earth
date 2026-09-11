-- Finance V2 Plan 4: derived Global Bank balance sheet.

CREATE TABLE IF NOT EXISTS global_bank_balance_sheet (
  game_day BIGINT PRIMARY KEY CHECK (game_day >= 0),
  reserve_units BIGINT NOT NULL CHECK (reserve_units >= 0),
  performing_loans_units BIGINT NOT NULL CHECK (performing_loans_units >= 0),
  impaired_loans_units BIGINT NOT NULL CHECK (impaired_loans_units >= 0),
  interest_receivable_units BIGINT NOT NULL CHECK (interest_receivable_units >= 0),
  deposit_principal_units BIGINT NOT NULL CHECK (deposit_principal_units >= 0),
  deposit_interest_payable_units BIGINT NOT NULL CHECK (deposit_interest_payable_units >= 0),
  withdrawals_payable_units BIGINT NOT NULL CHECK (withdrawals_payable_units >= 0),
  assets_units BIGINT NOT NULL,
  liabilities_units BIGINT NOT NULL,
  equity_units BIGINT NOT NULL,
  liquidity_ratio NUMERIC(20,8),
  capital_ratio NUMERIC(20,8),
  status TEXT NOT NULL CHECK (status IN ('healthy', 'illiquid', 'undercapitalized', 'insolvent')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS global_bank_balance_sheet_status_idx
  ON global_bank_balance_sheet (status, game_day DESC);

CREATE OR REPLACE FUNCTION earth_refresh_global_bank_balance_sheet(p_game_day BIGINT)
RETURNS global_bank_balance_sheet
LANGUAGE plpgsql
AS $$
DECLARE
  result global_bank_balance_sheet;
BEGIN
  INSERT INTO global_bank_balance_sheet (
    game_day, reserve_units, performing_loans_units, impaired_loans_units,
    interest_receivable_units, deposit_principal_units, deposit_interest_payable_units,
    withdrawals_payable_units, assets_units, liabilities_units, equity_units,
    liquidity_ratio, capital_ratio, status
  )
  WITH bank AS (
    SELECT COALESCE(SUM(a.balance), 0)::BIGINT AS reserve_units
    FROM economic_accounts a
    JOIN owner_registry o ON o.economic_id = a.owner_economic_id
    WHERE o.id = 'SYSTEM-GLOBAL-BANK' AND a.asset_id = 1 AND a.account_type = 10 AND a.status = 'active'
  ), loans AS (
    SELECT
      COALESCE(SUM(outstanding_principal_units) FILTER (WHERE status IN ('CURRENT', 'GRACE', 'DELINQUENT', 'RESTRUCTURED')), 0)::NUMERIC AS performing,
      COALESCE(SUM(outstanding_principal_units) FILTER (WHERE status = 'DEFAULTED'), 0)::NUMERIC AS impaired,
      COALESCE(SUM((outstanding_principal_units * rate_bps) / 10000) FILTER (WHERE status IN ('CURRENT', 'GRACE', 'DELINQUENT', 'RESTRUCTURED')), 0)::NUMERIC AS interest_receivable
    FROM bank_loans WHERE status NOT IN ('REPAID', 'WRITTEN_OFF')
  ), deposits AS (
    SELECT COALESCE(SUM(principal_units) FILTER (WHERE status IN ('ACTIVE', 'MATURED')), 0)::NUMERIC / 100 AS principal,
           COALESCE(SUM(accrued_interest_units) FILTER (WHERE status IN ('ACTIVE', 'MATURED')), 0)::NUMERIC / 100 AS interest,
           COALESCE(SUM(principal_units + accrued_interest_units) FILTER (WHERE status = 'MATURED'), 0)::NUMERIC / 100 AS withdrawals
    FROM bank_deposits
  ), components AS (
    SELECT b.reserve_units,
      ROUND(l.performing)::BIGINT AS performing_units,
      ROUND(l.impaired)::BIGINT AS impaired_units,
      ROUND(l.interest_receivable)::BIGINT AS interest_units,
      ROUND(d.principal * 100)::BIGINT AS principal_units,
      ROUND(d.interest * 100)::BIGINT AS deposit_interest_units,
      ROUND(d.withdrawals * 100)::BIGINT AS withdrawals_units
    FROM bank b CROSS JOIN loans l CROSS JOIN deposits d
  ), totals AS (
    SELECT *,
      reserve_units + performing_units + impaired_units + interest_units AS assets,
      principal_units + deposit_interest_units AS liabilities
    FROM components
  )
  SELECT p_game_day, reserve_units, performing_units, impaired_units, interest_units,
    principal_units, deposit_interest_units, withdrawals_units, assets, liabilities,
    assets - liabilities,
    CASE WHEN liabilities = 0 THEN NULL ELSE reserve_units::NUMERIC / liabilities END,
    CASE WHEN assets = 0 THEN NULL ELSE (assets - liabilities)::NUMERIC / assets END,
    CASE WHEN assets - liabilities < 0 THEN 'insolvent'
         WHEN assets = 0 OR (assets - liabilities)::NUMERIC / assets < 0.08 THEN 'undercapitalized'
         WHEN liabilities > 0 AND reserve_units < liabilities THEN 'illiquid'
         ELSE 'healthy' END
  FROM totals
  ON CONFLICT (game_day) DO UPDATE SET
    reserve_units = EXCLUDED.reserve_units,
    performing_loans_units = EXCLUDED.performing_loans_units,
    impaired_loans_units = EXCLUDED.impaired_loans_units,
    interest_receivable_units = EXCLUDED.interest_receivable_units,
    deposit_principal_units = EXCLUDED.deposit_principal_units,
    deposit_interest_payable_units = EXCLUDED.deposit_interest_payable_units,
    withdrawals_payable_units = EXCLUDED.withdrawals_payable_units,
    assets_units = EXCLUDED.assets_units,
    liabilities_units = EXCLUDED.liabilities_units,
    equity_units = EXCLUDED.equity_units,
    liquidity_ratio = EXCLUDED.liquidity_ratio,
    capital_ratio = EXCLUDED.capital_ratio,
    status = EXCLUDED.status,
    created_at = CURRENT_TIMESTAMP
  RETURNING * INTO result;
  RETURN result;
END;
$$;
