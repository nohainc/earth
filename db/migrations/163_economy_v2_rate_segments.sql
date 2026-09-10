-- Economy V2 Plan 14: compact intraday rate segments.
-- resource_rate_history remains available for legacy readers and analytics.

CREATE SEQUENCE IF NOT EXISTS settlement_rate_segments_id_seq
  AS BIGINT START WITH 1 INCREMENT BY 1 MINVALUE 1;

CREATE TABLE IF NOT EXISTS settlement_rate_segments (
  id BIGINT PRIMARY KEY DEFAULT nextval('settlement_rate_segments_id_seq'),
  owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  asset_id SMALLINT NOT NULL REFERENCES economic_assets(id),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  effective_from_minute SMALLINT NOT NULL CHECK (effective_from_minute BETWEEN 0 AND 1439),
  rate_units_per_day BIGINT NOT NULL,
  reason_code TEXT NOT NULL CHECK (length(btrim(reason_code)) > 0),
  source_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (owner_economic_id, asset_id, game_day, effective_from_minute)
);

CREATE INDEX IF NOT EXISTS settlement_rate_segments_day_idx
  ON settlement_rate_segments (game_day, owner_economic_id, asset_id, effective_from_minute);
CREATE INDEX IF NOT EXISTS settlement_rate_segments_owner_asset_idx
  ON settlement_rate_segments (owner_economic_id, asset_id, game_day DESC, effective_from_minute);

CREATE OR REPLACE FUNCTION earth_record_settlement_rate_segment(
  p_owner_economic_id BIGINT, p_asset_id SMALLINT, p_game_day BIGINT,
  p_effective_from_minute SMALLINT, p_rate_units_per_day BIGINT,
  p_reason_code TEXT, p_source_id TEXT DEFAULT NULL
)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT;
BEGIN
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

-- Weighted calculation in O(number of segments), with one final rounding step.
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
      (SELECT s.rate_units_per_day FROM settlement_rate_segments s
       WHERE s.owner_economic_id = $1 AND s.asset_id = $2 AND s.game_day = $3
         AND s.effective_from_minute <= i.start_minute
       ORDER BY s.effective_from_minute DESC LIMIT 1) AS rate
    FROM intervals i
  )
  SELECT COALESCE(ROUND(SUM(COALESCE(rate, 0)::NUMERIC * (end_minute - start_minute) / 1440)), 0)::BIGINT
  FROM rates WHERE end_minute > start_minute;
$$;
