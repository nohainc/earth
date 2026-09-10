-- Economy V2 Plan 25: canonical economic-state invalidation.

CREATE OR REPLACE FUNCTION earth_economic_state_changed(
  p_owner_id TEXT,
  p_entity_id TEXT,
  p_reason TEXT,
  p_game_day BIGINT DEFAULT NULL,
  p_game_minute INTEGER DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  -- Recalculate the rate first; earth_record_rate_change is extended by Plan
  -- 24 to write the corresponding V2 rate segments. Mark dirty afterwards so
  -- its compatibility profile update cannot accidentally leave the profile
  -- clean after the underlying building state changed.
  PERFORM earth_record_rate_change(p_owner_id, p_reason, p_entity_id, p_game_day, p_game_minute);

  UPDATE daily_settlement_profiles
  SET status = 'dirty',
      dirty_reason = p_reason,
      updated_at = CURRENT_TIMESTAMP
  WHERE owner_id = p_owner_id;
END;
$$;

COMMENT ON FUNCTION earth_economic_state_changed(TEXT, TEXT, TEXT, BIGINT, INTEGER)
IS 'Invalidates an owner settlement profile and records the resulting economic rate change.';
