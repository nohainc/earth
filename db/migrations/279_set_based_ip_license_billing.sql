-- Technology & Research V2 Plan 27: settle license fees set-wise.

ALTER FUNCTION earth_settle_technology_license_fees(BIGINT)
  RENAME TO earth_settle_technology_license_fees_policy;

CREATE OR REPLACE FUNCTION earth_settle_technology_license_fees(p_game_day BIGINT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
  v_effects JSONB;
  v_transaction_id BIGINT;
  v_paid BIGINT := 0;
BEGIN
  IF p_game_day < 0 THEN RAISE EXCEPTION 'Game day must be non-negative'; END IF;

  CREATE TEMP TABLE ip_license_due ON COMMIT DROP AS
  SELECT c.id AS contract_id, c.licensee_economic_id, c.licensor_economic_id,
         c.daily_fee_units, c.rules_version, payer.id AS payer_account_id,
         recipient.id AS recipient_account_id, payer.balance AS payer_balance
  FROM technology_license_contracts c
  LEFT JOIN LATERAL (
    SELECT a.id, a.balance
    FROM economic_accounts a
    WHERE a.owner_economic_id = c.licensee_economic_id AND a.asset_id = 1
      AND a.status = 'active' AND a.is_default_settlement
    ORDER BY a.id LIMIT 1
  ) payer ON TRUE
  LEFT JOIN LATERAL (
    SELECT a.id
    FROM economic_accounts a
    WHERE a.owner_economic_id = c.licensor_economic_id AND a.asset_id = 1
      AND a.status = 'active' AND a.is_default_settlement
    ORDER BY a.id LIMIT 1
  ) recipient ON TRUE
  WHERE c.status IN ('ACTIVE', 'SUSPENDED')
    AND c.daily_fee_units > 0
    AND c.effective_from_game_day <= p_game_day
    AND (c.effective_to_game_day IS NULL OR c.effective_to_game_day >= p_game_day)
    AND c.paid_through_game_day < p_game_day;

  -- Lock all accounts in stable order before resolving affordability. A
  -- licensee either funds all of its due contracts for this day or none of
  -- them, avoiding order-dependent partial payment.
  PERFORM 1 FROM economic_accounts a
  WHERE a.id IN (
    SELECT payer_account_id FROM ip_license_due WHERE payer_account_id IS NOT NULL
    UNION
    SELECT recipient_account_id FROM ip_license_due WHERE recipient_account_id IS NOT NULL
  )
  ORDER BY a.id FOR UPDATE;

  CREATE TEMP TABLE ip_license_funded ON COMMIT DROP AS
  SELECT d.*
  FROM ip_license_due d
  JOIN (
    SELECT payer_account_id, SUM(daily_fee_units) AS due_units,
           MAX(payer_balance) AS available_units
    FROM ip_license_due
    WHERE payer_account_id IS NOT NULL
    GROUP BY payer_account_id
  ) totals ON totals.payer_account_id = d.payer_account_id
  WHERE d.recipient_account_id IS NOT NULL
    AND totals.available_units >= totals.due_units;

  SELECT jsonb_agg(jsonb_build_object(
    'account_id', account_id, 'delta', delta, 'reason_code', 'IP_LICENSE_DAILY'
  ) ORDER BY account_id)
  INTO v_effects
  FROM (
    SELECT payer_account_id AS account_id, -SUM(daily_fee_units)::BIGINT AS delta
    FROM ip_license_funded GROUP BY payer_account_id
    UNION ALL
    SELECT recipient_account_id AS account_id, SUM(daily_fee_units)::BIGINT AS delta
    FROM ip_license_funded GROUP BY recipient_account_id
  ) grouped;

  IF v_effects IS NOT NULL THEN
    SELECT p.transaction_id INTO v_transaction_id
    FROM earth_post_settlement_batch(
      'ip-license-daily:' || p_game_day, p_game_day, 1439,
      'TECHNOLOGY_LICENSE', p_game_day::TEXT, 'ip-license-v2', v_effects
    ) p;

    INSERT INTO technology_license_payments (contract_id, game_day, amount_units, transaction_id, correlation_id)
    SELECT contract_id, p_game_day, daily_fee_units, v_transaction_id,
           'ip-license-daily:' || contract_id || ':' || p_game_day
    FROM ip_license_funded
    ON CONFLICT (contract_id, game_day) DO NOTHING;

    UPDATE technology_license_contracts c
    SET paid_through_game_day = p_game_day,
        last_daily_transaction_id = v_transaction_id,
        status = 'ACTIVE'
    FROM ip_license_funded f
    WHERE c.id = f.contract_id;
    SELECT COUNT(*) INTO v_paid FROM ip_license_funded;
  END IF;

  UPDATE technology_license_contracts c
  SET status = 'SUSPENDED'
  WHERE c.status = 'ACTIVE'
    AND c.daily_fee_units > 0
    AND c.effective_from_game_day <= p_game_day
    AND (c.effective_to_game_day IS NULL OR c.effective_to_game_day >= p_game_day)
    AND c.paid_through_game_day < p_game_day;

  UPDATE technology_license_contracts
  SET status = 'EXPIRED'
  WHERE status = 'SUSPENDED'
    AND effective_to_game_day IS NOT NULL
    AND effective_to_game_day < p_game_day;

  RETURN v_paid;
END;
$$;

COMMENT ON FUNCTION earth_settle_technology_license_fees(BIGINT) IS
  'Resolves affordability set-wise and posts one aggregated Economy V2 IP license batch per day.';
