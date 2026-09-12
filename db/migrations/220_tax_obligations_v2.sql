-- Finance V2 Plan 10: tax assessment is separate from tax payment.

CREATE TABLE IF NOT EXISTS tax_obligations (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  taxpayer_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  beneficiary_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  tax_type TEXT NOT NULL CHECK (tax_type IN ('basic_levy', 'personal_income', 'corporate_income', 'market_transaction', 'property', 'building')),
  tax_base_units BIGINT NOT NULL CHECK (tax_base_units >= 0),
  rate_bps INTEGER NOT NULL CHECK (rate_bps >= 0 AND rate_bps <= 10000),
  amount_units BIGINT NOT NULL CHECK (amount_units > 0),
  rule_version TEXT NOT NULL,
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  status TEXT NOT NULL DEFAULT 'DUE' CHECK (status IN ('DUE', 'PAID', 'PARTIAL', 'ARREARS', 'WAIVED')),
  payment_transaction_id BIGINT REFERENCES economic_transactions(id),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS tax_obligations_payment_idx
  ON tax_obligations(status, game_day, taxpayer_economic_id);

CREATE OR REPLACE FUNCTION earth_settle_v2_tax_obligations(p_game_day BIGINT)
RETURNS TABLE (
  obligations_considered BIGINT,
  obligations_paid BIGINT,
  obligations_partial BIGINT,
  obligations_arrears BIGINT,
  economic_transaction_id BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
  effects JSONB;
  posting RECORD;
BEGIN
  CREATE TEMP TABLE v2_tax_due ON COMMIT DROP AS
  SELECT t.id, t.amount_units, t.taxpayer_economic_id, t.beneficiary_economic_id,
         taxpayer.id AS taxpayer_account_id, beneficiary.id AS beneficiary_account_id,
         COALESCE(taxpayer.balance, 0)::BIGINT AS taxpayer_balance,
         LEAST(t.amount_units, COALESCE(taxpayer.balance, 0)::BIGINT) AS paid_units
  FROM tax_obligations t
  JOIN owner_registry taxpayer_owner ON taxpayer_owner.economic_id = t.taxpayer_economic_id
  JOIN owner_registry beneficiary_owner ON beneficiary_owner.economic_id = t.beneficiary_economic_id
  LEFT JOIN economic_accounts taxpayer
    ON taxpayer.owner_economic_id = t.taxpayer_economic_id
   AND taxpayer.asset_id = 1
   AND taxpayer.account_type = CASE WHEN taxpayer_owner.owner_type = 'human' THEN 1 ELSE 3 END
   AND taxpayer.is_default_settlement AND taxpayer.status = 'active'
  LEFT JOIN economic_accounts beneficiary
    ON beneficiary.owner_economic_id = t.beneficiary_economic_id
   AND beneficiary.asset_id = 1
   AND beneficiary.account_type = CASE WHEN beneficiary_owner.owner_type = 'human' THEN 1 ELSE 3 END
   AND beneficiary.is_default_settlement AND beneficiary.status = 'active'
  WHERE t.status IN ('DUE', 'PARTIAL', 'ARREARS') AND t.game_day <= p_game_day
  FOR UPDATE OF t;

  SELECT COUNT(*) INTO obligations_considered FROM v2_tax_due;
  PERFORM 1 FROM economic_accounts a
  JOIN v2_tax_due d ON a.id IN (d.taxpayer_account_id, d.beneficiary_account_id)
  ORDER BY a.id FOR UPDATE;

  SELECT jsonb_agg(jsonb_build_object('account_id', account_id, 'delta', delta, 'reason_code', 'TAX_PAYMENT') ORDER BY account_id)
    INTO effects
  FROM (
    SELECT taxpayer_account_id AS account_id, -SUM(paid_units) AS delta FROM v2_tax_due
    WHERE paid_units > 0 AND taxpayer_account_id IS NOT NULL GROUP BY taxpayer_account_id
    UNION ALL
    SELECT beneficiary_account_id AS account_id, SUM(paid_units) AS delta FROM v2_tax_due
    WHERE paid_units > 0 AND beneficiary_account_id IS NOT NULL GROUP BY beneficiary_account_id
  ) grouped_effects
  WHERE account_id IS NOT NULL;

  IF effects IS NOT NULL AND jsonb_array_length(effects) >= 2 THEN
    SELECT * INTO posting FROM earth_post_settlement_batch(
      format('tax-settlement:%s', p_game_day), p_game_day, 1439,
      'tax_authority', 'OUC', 'finance-v2', effects
    );
    economic_transaction_id := posting.transaction_id;
  END IF;

  UPDATE tax_obligations t SET
    status = CASE WHEN d.paid_units >= d.amount_units THEN 'PAID'
                  WHEN d.paid_units > 0 THEN 'PARTIAL' ELSE 'ARREARS' END,
    payment_transaction_id = CASE WHEN d.paid_units > 0 THEN economic_transaction_id ELSE t.payment_transaction_id END,
    updated_at = CURRENT_TIMESTAMP
  FROM v2_tax_due d WHERE t.id = d.id;

  SELECT COUNT(*) FILTER (WHERE paid_units >= amount_units),
         COUNT(*) FILTER (WHERE paid_units > 0 AND paid_units < amount_units),
         COUNT(*) FILTER (WHERE paid_units = 0)
    INTO obligations_paid, obligations_partial, obligations_arrears
  FROM v2_tax_due;
  RETURN NEXT;
END;
$$;
