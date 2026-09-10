-- Economy V2 Plan 5: database-enforced idempotency for economic operations.

ALTER TABLE economic_transactions
  ADD CONSTRAINT economic_transactions_correlation_nonempty_ck
  CHECK (length(btrim(correlation_id)) > 0);

CREATE OR REPLACE FUNCTION earth_begin_economic_transaction(
  p_correlation_id TEXT,
  p_game_day BIGINT,
  p_game_minute SMALLINT,
  p_transaction_kind TEXT,
  p_source_type TEXT,
  p_source_id TEXT,
  p_rules_version TEXT
)
RETURNS TABLE (
  transaction_id BIGINT,
  correlation_id TEXT,
  created BOOLEAN
)
LANGUAGE plpgsql
AS $$
DECLARE
  existing economic_transactions%ROWTYPE;
BEGIN
  IF p_correlation_id IS NULL OR length(btrim(p_correlation_id)) = 0 THEN
    RAISE EXCEPTION 'Economic transaction correlation_id is required';
  END IF;

  INSERT INTO economic_transactions (
    correlation_id, game_day, game_minute, transaction_kind,
    source_type, source_id, rules_version
  ) VALUES (
    p_correlation_id, p_game_day, p_game_minute, p_transaction_kind,
    p_source_type, p_source_id, p_rules_version
  )
  ON CONFLICT (correlation_id) DO NOTHING
  RETURNING id, economic_transactions.correlation_id
  INTO transaction_id, correlation_id;

  IF transaction_id IS NOT NULL THEN
    created := TRUE;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT * INTO existing
  FROM economic_transactions
  WHERE economic_transactions.correlation_id = p_correlation_id;

  IF existing.game_day <> p_game_day
     OR existing.game_minute <> p_game_minute
     OR existing.transaction_kind <> p_transaction_kind
     OR existing.source_type <> p_source_type
     OR existing.source_id IS DISTINCT FROM p_source_id
     OR existing.rules_version <> p_rules_version THEN
    RAISE EXCEPTION 'Correlation ID % was already used with different transaction parameters', p_correlation_id;
  END IF;

  transaction_id := existing.id;
  correlation_id := existing.correlation_id;
  created := FALSE;
  RETURN NEXT;
END;
$$;
