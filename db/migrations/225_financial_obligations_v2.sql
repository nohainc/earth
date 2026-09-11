-- Finance V2 Plan 15: one liability model for insolvency decisions.

CREATE OR REPLACE VIEW financial_obligations AS
SELECT l.id::TEXT AS source_id,
       l.borrower_economic_id AS debtor_economic_id,
       bank.economic_id AS creditor_economic_id,
       'BANK_LOAN'::TEXT AS obligation_type,
       l.outstanding_principal_units AS principal_due_units,
       l.accrued_interest_units AS interest_due_units,
       COALESCE(l.next_payment_game_day, l.origination_total_game_minute / 1440) AS due_game_day,
       20 AS priority_class,
       l.status
FROM bank_loans l
JOIN owner_registry bank ON bank.id = 'SYSTEM-GLOBAL-BANK'
WHERE l.status NOT IN ('REPAID', 'WRITTEN_OFF')
UNION ALL
SELECT t.id::TEXT AS source_id,
       t.taxpayer_economic_id AS debtor_economic_id,
       t.beneficiary_economic_id AS creditor_economic_id,
       'TAX'::TEXT AS obligation_type,
       t.amount_units AS principal_due_units,
       0::BIGINT AS interest_due_units,
       t.game_day AS due_game_day,
       10 AS priority_class,
       t.status
FROM tax_obligations t
WHERE t.status NOT IN ('PAID', 'WAIVED');

CREATE OR REPLACE FUNCTION earth_personal_insolvency_metrics(p_debtor_economic_id BIGINT, p_game_day BIGINT)
RETURNS TABLE (
  due_units BIGINT,
  liabilities_units BIGINT,
  realizable_assets_units BIGINT,
  liquid_units BIGINT,
  serviceable BOOLEAN,
  materially_insolvent BOOLEAN
)
LANGUAGE SQL
STABLE
AS $$
  WITH obligations AS (
    SELECT COALESCE(SUM(principal_due_units + interest_due_units) FILTER (WHERE due_game_day <= p_game_day), 0)::BIGINT AS due_units,
           COALESCE(SUM(principal_due_units + interest_due_units), 0)::BIGINT AS liabilities_units
    FROM financial_obligations WHERE debtor_economic_id = p_debtor_economic_id
  ), assets AS (
    SELECT COALESCE(SUM(balance) FILTER (WHERE asset_id = 1 AND account_type NOT IN (7, 8)), 0)::BIGINT AS liquid_units,
           COALESCE(SUM(balance) FILTER (WHERE account_type NOT IN (7, 8)), 0)::BIGINT AS realizable_assets_units
    FROM economic_accounts WHERE owner_economic_id = p_debtor_economic_id AND status = 'active'
  )
  SELECT o.due_units, o.liabilities_units, a.realizable_assets_units, a.liquid_units,
         a.liquid_units >= o.due_units,
         o.liabilities_units > a.realizable_assets_units
  FROM obligations o CROSS JOIN assets a;
$$;
