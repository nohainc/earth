-- Economy V2 Plan 10: bulk posting for one ordered settlement phase/shard.
-- This consumes settlement_effect_nets, never posts one transaction per owner,
-- and never calls earth_post_transaction per effect.

CREATE OR REPLACE FUNCTION earth_post_settlement_phase(
  p_game_day BIGINT,
  p_phase TEXT,
  p_shard SMALLINT,
  p_rules_version TEXT
)
RETURNS TABLE (
  transaction_id BIGINT,
  created BOOLEAN,
  entry_count BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
  transaction_created BOOLEAN;
  v_transaction_id BIGINT;
  missing_count BIGINT;
  invalid_count BIGINT;
BEGIN
  IF p_phase IS NULL OR length(btrim(p_phase)) = 0 THEN
    RAISE EXCEPTION 'Settlement phase is required';
  END IF;
  IF p_shard < 0 OR p_shard > 63 THEN
    RAISE EXCEPTION 'Settlement shard must be between 0 and 63';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM settlement_effect_nets
    WHERE game_day = p_game_day AND phase = p_phase AND shard = p_shard
  ) THEN
    RAISE EXCEPTION 'Settlement phase %/%/% has no net effects', p_game_day, p_phase, p_shard;
  END IF;

  SELECT b.transaction_id, b.created
  INTO v_transaction_id, transaction_created
  FROM earth_begin_economic_transaction(
    'settlement:' || p_game_day || ':' || p_phase || ':' || p_shard,
    p_game_day, 0, 'SETTLEMENT_BATCH', 'scheduler',
    p_phase || ':' || p_shard, p_rules_version
  ) b;
  transaction_id := v_transaction_id;
  created := transaction_created;

  IF NOT transaction_created THEN
    SELECT COUNT(*) INTO entry_count
    FROM economic_entries
    WHERE economic_entries.transaction_id = v_transaction_id;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT COUNT(*) INTO missing_count
  FROM settlement_effect_nets n
  LEFT JOIN economic_accounts a ON a.id = n.account_id
  WHERE n.game_day = p_game_day AND n.phase = p_phase AND n.shard = p_shard
    AND a.id IS NULL;
  IF missing_count > 0 THEN
    RAISE EXCEPTION 'Settlement phase references % missing accounts', missing_count;
  END IF;

  -- Lock each affected account once, in ascending account order.
  PERFORM 1
  FROM economic_accounts a
  JOIN settlement_effect_nets n ON n.account_id = a.id
  WHERE n.game_day = p_game_day AND n.phase = p_phase AND n.shard = p_shard
  GROUP BY a.id
  ORDER BY a.id
  FOR UPDATE;

  WITH totals AS (
    SELECT account_id, SUM(delta)::BIGINT AS delta
    FROM settlement_effect_nets
    WHERE game_day = p_game_day AND phase = p_phase AND shard = p_shard
    GROUP BY account_id
  )
  SELECT COUNT(*) INTO invalid_count
  FROM totals t
  JOIN economic_accounts a ON a.id = t.account_id
  WHERE a.status <> 'active' OR a.balance + t.delta < 0;
  IF invalid_count > 0 THEN
    RAISE EXCEPTION 'Settlement phase has % invalid or insufficient account balances', invalid_count;
  END IF;

  WITH totals AS (
    SELECT account_id, SUM(delta)::BIGINT AS delta
    FROM settlement_effect_nets
    WHERE game_day = p_game_day AND phase = p_phase AND shard = p_shard
    GROUP BY account_id
  )
  UPDATE economic_accounts a
  SET balance = a.balance + totals.delta,
      updated_at = CURRENT_TIMESTAMP
  FROM totals
  WHERE a.id = totals.account_id;

  INSERT INTO economic_entries (transaction_id, account_id, game_day, delta, reason_code)
  SELECT v_transaction_id, n.account_id, n.game_day, n.delta, n.reason_code
  FROM settlement_effect_nets n
  WHERE n.game_day = p_game_day AND n.phase = p_phase AND n.shard = p_shard;

  SELECT COUNT(*) INTO entry_count
  FROM economic_entries
  WHERE economic_entries.transaction_id = v_transaction_id;
  RETURN NEXT;
END;
$$;
