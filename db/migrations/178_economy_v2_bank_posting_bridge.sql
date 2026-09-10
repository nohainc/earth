-- Economy V2 Plan 30: route bank deposit/withdrawal transfers through the
-- V2 posting primitive while dual-writing the legacy ledger during cutover.

CREATE OR REPLACE FUNCTION earth_post_legacy_credit_transfer(
  p_ledger_id UUID,
  p_game_day BIGINT,
  p_debit_account TEXT,
  p_credit_account TEXT,
  p_amount NUMERIC,
  p_reason_type TEXT,
  p_reason_id TEXT,
  p_rule_version TEXT,
  p_correlation_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  v_debit BIGINT;
  v_credit BIGINT;
  v_units BIGINT;
BEGIN
  SELECT economic_account_id INTO v_debit
  FROM economic_account_migrations WHERE legacy_account_id = p_debit_account;
  SELECT economic_account_id INTO v_credit
  FROM economic_account_migrations WHERE legacy_account_id = p_credit_account;
  IF v_debit IS NULL OR v_credit IS NULL THEN
    RAISE EXCEPTION 'V2 account mapping is missing for legacy transfer % -> %', p_debit_account, p_credit_account;
  END IF;
  v_units := ROUND(p_amount * 100)::BIGINT;
  PERFORM * FROM earth_post_transaction(
    p_correlation_id, p_game_day, 0, p_reason_type, 'interactive', p_reason_id,
    p_rule_version,
    jsonb_build_array(
      jsonb_build_object('account_id', v_debit, 'delta', -v_units, 'reason_code', p_reason_type),
      jsonb_build_object('account_id', v_credit, 'delta', v_units, 'reason_code', p_reason_type)
    )
  );
  PERFORM earth_transfer_credits(
    p_ledger_id, p_game_day, p_debit_account, p_credit_account, p_amount,
    p_reason_type, p_reason_id, p_rule_version, p_correlation_id
  );
END;
$$;

DO $$
DECLARE
  function_name TEXT;
  definition_text TEXT;
BEGIN
  FOREACH function_name IN ARRAY ARRAY['earth_create_bank_deposit', 'earth_withdraw_bank_deposit'] LOOP
    SELECT pg_get_functiondef(p.oid) INTO definition_text
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = function_name
    LIMIT 1;
    IF definition_text IS NULL THEN
      RAISE EXCEPTION 'Cannot locate % for V2 bank bridge', function_name;
    END IF;
    definition_text := replace(definition_text, 'earth_transfer_credits(', 'earth_post_legacy_credit_transfer(');
    EXECUTE definition_text;
  END LOOP;
END;
$$;
