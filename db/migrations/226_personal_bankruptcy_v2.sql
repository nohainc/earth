-- Finance V2 Plan 16: explicit personal bankruptcy proceedings.

ALTER TABLE personal_financial_states DROP CONSTRAINT IF EXISTS personal_financial_states_status_check;
ALTER TABLE personal_financial_states ADD CONSTRAINT personal_financial_states_status_check
  CHECK (status IN ('active', 'distressed', 'insolvent', 'insolvency_proceeding', 'bankrupt'));

CREATE TABLE IF NOT EXISTS bankruptcy_proceedings (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  debtor_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  human_id TEXT NOT NULL REFERENCES humans(id),
  status TEXT NOT NULL CHECK (status IN ('OPEN', 'FROZEN', 'RESOLVED', 'FAILED')),
  opened_game_day BIGINT NOT NULL,
  resolved_game_day BIGINT,
  due_obligations_units BIGINT NOT NULL DEFAULT 0,
  liabilities_units BIGINT NOT NULL DEFAULT 0,
  realizable_assets_units BIGINT NOT NULL DEFAULT 0,
  liquid_assets_units BIGINT NOT NULL DEFAULT 0,
  estate_value_units BIGINT NOT NULL DEFAULT 0,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS bankruptcy_proceedings_status_idx ON bankruptcy_proceedings(status, opened_game_day);

CREATE TABLE IF NOT EXISTS bankruptcy_estate_assets (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  proceeding_id BIGINT NOT NULL REFERENCES bankruptcy_proceedings(id) ON DELETE CASCADE,
  account_id BIGINT,
  asset_id SMALLINT,
  asset_units BIGINT NOT NULL DEFAULT 0,
  liquidation_value_units BIGINT NOT NULL DEFAULT 0,
  protected BOOLEAN NOT NULL DEFAULT FALSE,
  source_kind TEXT NOT NULL CHECK (source_kind IN ('economic_account', 'building', 'resource')),
  source_id TEXT NOT NULL,
  UNIQUE (proceeding_id, source_kind, source_id)
);

CREATE TABLE IF NOT EXISTS bankruptcy_claims (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  proceeding_id BIGINT NOT NULL REFERENCES bankruptcy_proceedings(id) ON DELETE CASCADE,
  creditor_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  obligation_type TEXT NOT NULL,
  source_id TEXT NOT NULL,
  priority SMALLINT NOT NULL,
  amount_units BIGINT NOT NULL CHECK (amount_units >= 0),
  paid_units BIGINT NOT NULL DEFAULT 0 CHECK (paid_units >= 0 AND paid_units <= amount_units),
  status TEXT NOT NULL DEFAULT 'DUE' CHECK (status IN ('DUE', 'PARTIAL', 'PAID', 'WRITTEN_OFF')),
  UNIQUE (proceeding_id, obligation_type, source_id)
);
CREATE INDEX IF NOT EXISTS bankruptcy_estate_assets_proceeding_idx ON bankruptcy_estate_assets(proceeding_id);
CREATE INDEX IF NOT EXISTS bankruptcy_claims_proceeding_priority_idx ON bankruptcy_claims(proceeding_id, priority, id);

CREATE OR REPLACE FUNCTION earth_open_personal_bankruptcy(p_human_id TEXT, p_game_day BIGINT, p_correlation_id TEXT)
RETURNS bankruptcy_proceedings LANGUAGE plpgsql AS $$
DECLARE
  existing bankruptcy_proceedings;
  owner_row RECORD;
  metrics RECORD;
  result bankruptcy_proceedings;
BEGIN
  SELECT * INTO existing FROM bankruptcy_proceedings WHERE correlation_id = p_correlation_id;
  IF FOUND THEN RETURN existing; END IF;
  SELECT o.economic_id INTO owner_row FROM owner_registry o WHERE o.id = p_human_id AND o.owner_type = 'human' AND o.status = 'active';
  IF owner_row.economic_id IS NULL THEN RAISE EXCEPTION 'Bankruptcy debtor is unavailable'; END IF;
  SELECT * INTO metrics FROM earth_personal_insolvency_metrics(owner_row.economic_id, p_game_day);
  IF metrics.serviceable OR NOT metrics.materially_insolvent THEN RAISE EXCEPTION 'Personal insolvency criteria are not met'; END IF;
  INSERT INTO bankruptcy_proceedings (debtor_economic_id, human_id, status, opened_game_day, due_obligations_units, liabilities_units, realizable_assets_units, liquid_assets_units, estate_value_units, correlation_id)
  VALUES (owner_row.economic_id, p_human_id, 'FROZEN', p_game_day, metrics.due_units, metrics.liabilities_units, metrics.realizable_assets_units, metrics.liquid_units, metrics.realizable_assets_units, p_correlation_id)
  RETURNING * INTO result;
  INSERT INTO personal_financial_states (human_id, status, since_game_day, last_reason) VALUES (p_human_id, 'insolvency_proceeding', p_game_day, 'V2 bankruptcy proceeding opened')
  ON CONFLICT (human_id) DO UPDATE SET status = 'insolvency_proceeding', since_game_day = EXCLUDED.since_game_day, last_reason = EXCLUDED.last_reason, updated_at = CURRENT_TIMESTAMP;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION earth_reject_frozen_personal_loan_or_order()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE owner_id TEXT;
BEGIN
  IF TG_TABLE_NAME = 'bank_loans' THEN SELECT id INTO owner_id FROM owner_registry WHERE economic_id = NEW.borrower_economic_id;
  ELSE SELECT id INTO owner_id FROM owner_registry WHERE economic_id = NEW.owner_economic_id; END IF;
  IF EXISTS (SELECT 1 FROM personal_financial_states WHERE human_id = owner_id AND status = 'insolvency_proceeding') THEN
    RAISE EXCEPTION 'Personal insolvency proceeding blocks new loans and market orders';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS bank_loans_reject_frozen_owner ON bank_loans;
CREATE TRIGGER bank_loans_reject_frozen_owner BEFORE INSERT ON bank_loans FOR EACH ROW EXECUTE FUNCTION earth_reject_frozen_personal_loan_or_order();
DROP TRIGGER IF EXISTS market_orders_reject_frozen_owner ON market_orders;
CREATE TRIGGER market_orders_reject_frozen_owner BEFORE INSERT ON market_orders FOR EACH ROW EXECUTE FUNCTION earth_reject_frozen_personal_loan_or_order();
