-- Economy V2 Plan 24: make intraday rate segments self-contained.

CREATE OR REPLACE FUNCTION earth_record_settlement_rate_segment(
  p_owner_economic_id BIGINT, p_asset_id SMALLINT, p_game_day BIGINT,
  p_effective_from_minute SMALLINT, p_rate_units_per_day BIGINT,
  p_reason_code TEXT, p_source_id TEXT DEFAULT NULL
)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
  v_id BIGINT;
  v_baseline BIGINT;
BEGIN
  IF p_effective_from_minute > 0 THEN
    -- A rate change in the middle of a day needs the rate that was active at
    -- day start. Prefer the latest prior-day segment; a never-active owner
    -- starts at zero.
    SELECT s.rate_units_per_day INTO v_baseline
    FROM settlement_rate_segments s
    WHERE s.owner_economic_id = p_owner_economic_id
      AND s.asset_id = p_asset_id
      AND s.game_day < p_game_day
    ORDER BY s.game_day DESC, s.effective_from_minute DESC, s.id DESC
    LIMIT 1;
    v_baseline := COALESCE(v_baseline, 0);

    INSERT INTO settlement_rate_segments (
      owner_economic_id, asset_id, game_day, effective_from_minute,
      rate_units_per_day, reason_code, source_id
    ) VALUES (
      p_owner_economic_id, p_asset_id, p_game_day, 0,
      v_baseline, 'daily_baseline', p_source_id
    )
    ON CONFLICT (owner_economic_id, asset_id, game_day, effective_from_minute)
    DO NOTHING;
  END IF;

  INSERT INTO settlement_rate_segments (
    owner_economic_id, asset_id, game_day, effective_from_minute,
    rate_units_per_day, reason_code, source_id
  ) VALUES (
    p_owner_economic_id, p_asset_id, p_game_day, p_effective_from_minute,
    p_rate_units_per_day, p_reason_code, p_source_id
  )
  ON CONFLICT (owner_economic_id, asset_id, game_day, effective_from_minute)
  DO UPDATE SET rate_units_per_day = EXCLUDED.rate_units_per_day,
                reason_code = EXCLUDED.reason_code,
                source_id = EXCLUDED.source_id
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- Keep the calculator correct for stable owners whose baseline has not yet
-- been materialized by an event. New event-driven rows are self-contained.
CREATE OR REPLACE FUNCTION earth_calculate_intraday_rate_units(
  p_owner_economic_id BIGINT, p_asset_id SMALLINT, p_game_day BIGINT,
  p_from_minute SMALLINT DEFAULT 0, p_to_minute SMALLINT DEFAULT 1440
)
RETURNS BIGINT LANGUAGE sql STABLE AS $$
  WITH points AS (
    SELECT $4::SMALLINT AS minute
    UNION
    SELECT effective_from_minute FROM settlement_rate_segments
    WHERE owner_economic_id = $1 AND asset_id = $2 AND game_day = $3
      AND effective_from_minute > $4 AND effective_from_minute < $5
    UNION
    SELECT $5::SMALLINT
  ), intervals AS (
    SELECT minute AS start_minute, LEAD(minute) OVER (ORDER BY minute) AS end_minute FROM points
  ), rates AS (
    SELECT i.start_minute, i.end_minute,
      COALESCE(
        (SELECT s.rate_units_per_day FROM settlement_rate_segments s
         WHERE s.owner_economic_id = $1 AND s.asset_id = $2 AND s.game_day = $3
           AND s.effective_from_minute <= i.start_minute
         ORDER BY s.effective_from_minute DESC, s.id DESC LIMIT 1),
        (SELECT s.rate_units_per_day FROM settlement_rate_segments s
         WHERE s.owner_economic_id = $1 AND s.asset_id = $2 AND s.game_day < $3
         ORDER BY s.game_day DESC, s.effective_from_minute DESC, s.id DESC LIMIT 1),
        0
      ) AS rate
    FROM intervals i
  )
  SELECT COALESCE(ROUND(SUM(COALESCE(rate, 0)::NUMERIC * (end_minute - start_minute) / 1440)), 0)::BIGINT
  FROM rates WHERE end_minute > start_minute;
$$;

-- Existing building activation, demolition, and operating-policy changes all
-- call earth_record_rate_change. Extend that procedure so every such event
-- records V2 rates for all six assets at the event's game minute.
DO $$
DECLARE
  definition_text TEXT;
  old_declaration TEXT := '  v_owner_kind TEXT;';
  new_declaration TEXT := E'  v_owner_kind TEXT;\n  v_owner_economic_id BIGINT;';
  old_marker TEXT := '  -- Also update daily_settlement_profiles with the new clean net rates and subtotal columns';
  new_marker TEXT := $insert$
  SELECT economic_id INTO v_owner_economic_id FROM owner_registry WHERE id = p_owner_id;
  IF v_owner_economic_id IS NOT NULL THEN
    PERFORM earth_record_settlement_rate_segment(v_owner_economic_id, 1, v_game_day, v_game_minute::SMALLINT, ROUND((v_in_credits - v_out_credits - v_tax_credits) * 100)::BIGINT, p_trigger_event, p_trigger_entity_id);
    PERFORM earth_record_settlement_rate_segment(v_owner_economic_id, 2, v_game_day, v_game_minute::SMALLINT, ROUND((v_in_material - v_out_material) * 1000000)::BIGINT, p_trigger_event, p_trigger_entity_id);
    PERFORM earth_record_settlement_rate_segment(v_owner_economic_id, 3, v_game_day, v_game_minute::SMALLINT, ROUND((v_in_components - v_out_components) * 1000000)::BIGINT, p_trigger_event, p_trigger_entity_id);
    PERFORM earth_record_settlement_rate_segment(v_owner_economic_id, 4, v_game_day, v_game_minute::SMALLINT, ROUND((v_in_energy - v_out_energy) * 1000000)::BIGINT, p_trigger_event, p_trigger_entity_id);
    PERFORM earth_record_settlement_rate_segment(v_owner_economic_id, 5, v_game_day, v_game_minute::SMALLINT, ROUND((v_in_compute - v_out_compute) * 1000000)::BIGINT, p_trigger_event, p_trigger_entity_id);
    PERFORM earth_record_settlement_rate_segment(v_owner_economic_id, 6, v_game_day, v_game_minute::SMALLINT, ROUND((v_in_food - v_out_food) * 1000000)::BIGINT, p_trigger_event, p_trigger_entity_id);
  END IF;

  -- Also update daily_settlement_profiles with the new clean net rates and subtotal columns$insert$;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO definition_text
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'earth_record_rate_change'
  LIMIT 1;
  IF definition_text IS NULL OR position(old_declaration IN definition_text) = 0 OR position(old_marker IN definition_text) = 0 THEN
    RAISE EXCEPTION 'Cannot extend earth_record_rate_change for V2 rate segments';
  END IF;
  definition_text := replace(definition_text, old_declaration, new_declaration);
  definition_text := replace(definition_text, old_marker, new_marker);
  EXECUTE definition_text;
END;
$$;
