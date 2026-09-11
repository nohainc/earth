-- Cities, Corporations & Budgets V2 Plan 30.
-- Institutional narrative only; Economy V2 remains the value authority.

CREATE TABLE IF NOT EXISTS institution_financial_events (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  institution_id TEXT NOT NULL REFERENCES institutions(id),
  game_day BIGINT NOT NULL,
  event_type TEXT NOT NULL,
  amount_units BIGINT NOT NULL DEFAULT 0 CHECK (amount_units >= 0),
  budget_line_id BIGINT REFERENCES institution_budget_lines(id),
  economic_transaction_id BIGINT REFERENCES economic_transactions(id),
  source_id TEXT,
  actor_human_id TEXT REFERENCES humans(id),
  proposal_id TEXT,
  correlation_id TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (institution_id, event_type, correlation_id)
);
CREATE INDEX IF NOT EXISTS institution_financial_events_timeline_idx
  ON institution_financial_events(institution_id, game_day DESC, id DESC);
CREATE INDEX IF NOT EXISTS institution_financial_events_transaction_idx
  ON institution_financial_events(economic_transaction_id);

CREATE OR REPLACE FUNCTION earth_record_institution_financial_event(
  p_institution_id TEXT,
  p_game_day BIGINT,
  p_event_type TEXT,
  p_amount_units BIGINT DEFAULT 0,
  p_budget_line_id BIGINT DEFAULT NULL,
  p_economic_transaction_id BIGINT DEFAULT NULL,
  p_source_id TEXT DEFAULT NULL,
  p_actor_human_id TEXT DEFAULT NULL,
  p_proposal_id TEXT DEFAULT NULL,
  p_correlation_id TEXT DEFAULT NULL
)
RETURNS BIGINT LANGUAGE SQL AS $$
  INSERT INTO institution_financial_events
    (institution_id, game_day, event_type, amount_units, budget_line_id,
     economic_transaction_id, source_id, actor_human_id, proposal_id, correlation_id)
  VALUES ($1,$2,$3,COALESCE($4,0),$5,$6,$7,$8,$9,COALESCE($10, format('%s:%s:%s', $1, $3, $2)))
  ON CONFLICT (institution_id, event_type, correlation_id) DO UPDATE SET amount_units = EXCLUDED.amount_units
  RETURNING id;
$$;
