-- Cities, Corporations & Budgets V2 Plan 3.
-- Budget authorizations belong to strategic fiscal periods, not individual
-- scheduler days.

CREATE TABLE IF NOT EXISTS fiscal_periods (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  period_type TEXT NOT NULL CHECK (period_type IN ('MONTH', 'QUARTER', 'YEAR', 'SPECIAL')),
  start_game_day BIGINT NOT NULL CHECK (start_game_day >= 1),
  end_game_day BIGINT NOT NULL CHECK (end_game_day >= start_game_day),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('PLANNED', 'ACTIVE', 'CLOSED', 'CANCELLED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (start_game_day, end_game_day)
);

ALTER TABLE institution_budget_lines
  ADD COLUMN IF NOT EXISTS fiscal_period_id BIGINT;

-- Existing V2 lines were daily authorizations. Preserve them as explicit
-- one-day SPECIAL periods before removing the raw game_period column.
INSERT INTO fiscal_periods (period_type, start_game_day, end_game_day, status)
SELECT 'SPECIAL', GREATEST(game_period, 1), GREATEST(game_period, 1), 'CLOSED'
FROM institution_budget_lines
WHERE game_period >= 0
GROUP BY game_period
ON CONFLICT (start_game_day, end_game_day) DO NOTHING;

UPDATE institution_budget_lines b
SET fiscal_period_id = p.id
FROM fiscal_periods p
WHERE p.start_game_day = GREATEST(b.game_period, 1)
  AND p.end_game_day = GREATEST(b.game_period, 1)
  AND b.fiscal_period_id IS NULL;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM institution_budget_lines WHERE fiscal_period_id IS NULL) THEN
    RAISE EXCEPTION 'Cannot migrate budget lines without a fiscal period';
  END IF;
END;
$$;

ALTER TABLE institution_budget_lines
  DROP CONSTRAINT IF EXISTS institution_budget_lines_pkey;
ALTER TABLE institution_budget_lines
  DROP COLUMN IF EXISTS game_period,
  ALTER COLUMN fiscal_period_id SET NOT NULL;
ALTER TABLE institution_budget_lines
  ADD CONSTRAINT institution_budget_lines_fiscal_period_fk
  FOREIGN KEY (fiscal_period_id) REFERENCES fiscal_periods(id);
ALTER TABLE institution_budget_lines
  ADD CONSTRAINT institution_budget_lines_pkey
  PRIMARY KEY (institution_id, fiscal_period_id, category);

DROP INDEX IF EXISTS institution_budget_lines_period_idx;
CREATE INDEX IF NOT EXISTS institution_budget_lines_period_idx
  ON institution_budget_lines(fiscal_period_id, institution_id, category);

CREATE OR REPLACE FUNCTION earth_fiscal_period_for_day(p_game_day BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
  v_length BIGINT;
  v_start BIGINT;
  v_end BIGINT;
  v_id BIGINT;
BEGIN
  IF p_game_day < 1 THEN
    RAISE EXCEPTION 'Fiscal periods require game day >= 1';
  END IF;
  SELECT GREATEST(1, COALESCE(NULLIF(value, '')::BIGINT, 30))
  INTO v_length
  FROM world_rules
  WHERE key = 'fiscal_period.standard_length_game_days';
  v_length := COALESCE(v_length, 30);
  v_start := ((p_game_day - 1) / v_length) * v_length + 1;
  v_end := v_start + v_length - 1;

  INSERT INTO fiscal_periods (period_type, start_game_day, end_game_day, status)
  VALUES ('MONTH', v_start, v_end, 'ACTIVE')
  ON CONFLICT (start_game_day, end_game_day) DO UPDATE SET status = CASE
    WHEN fiscal_periods.status = 'CANCELLED' THEN 'ACTIVE'
    ELSE fiscal_periods.status
  END
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    SELECT id INTO v_id FROM fiscal_periods
    WHERE start_game_day = v_start AND end_game_day = v_end;
  END IF;
  RETURN v_id;
END;
$$;

COMMENT ON TABLE fiscal_periods IS
  'Strategic authorization periods for institutional budgets; standard length is configurable via world_rules.';
