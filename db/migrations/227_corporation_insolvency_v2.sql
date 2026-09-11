-- Finance V2 Plan 17: corporate insolvency has its own lifecycle and estate.

ALTER TABLE financial_states DROP CONSTRAINT IF EXISTS financial_states_status_check;
ALTER TABLE financial_states ADD CONSTRAINT financial_states_status_check
  CHECK (status IN ('active','distressed','restructuring','insolvent','liquidation','bankrupt','dissolved'));

CREATE TABLE IF NOT EXISTS corporation_insolvency_proceedings (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  institution_id TEXT NOT NULL REFERENCES institutions(id),
  debtor_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  status TEXT NOT NULL CHECK (status IN ('RESTRUCTURING','INSOLVENT','LIQUIDATION','DISSOLVED','FAILED')),
  opened_game_day BIGINT NOT NULL,
  liquidation_game_day BIGINT,
  resolved_game_day BIGINT,
  liabilities_units BIGINT NOT NULL DEFAULT 0,
  estate_value_units BIGINT NOT NULL DEFAULT 0,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (institution_id, status)
);

CREATE TABLE IF NOT EXISTS corporation_estate_assets (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  proceeding_id BIGINT NOT NULL REFERENCES corporation_insolvency_proceedings(id) ON DELETE CASCADE,
  account_id BIGINT,
  asset_id SMALLINT,
  asset_units BIGINT NOT NULL DEFAULT 0,
  liquidation_value_units BIGINT NOT NULL DEFAULT 0,
  source_kind TEXT NOT NULL CHECK (source_kind IN ('economic_account','building','resource')),
  source_id TEXT NOT NULL,
  UNIQUE (proceeding_id, source_kind, source_id)
);

CREATE TABLE IF NOT EXISTS corporation_creditor_claims (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  proceeding_id BIGINT NOT NULL REFERENCES corporation_insolvency_proceedings(id) ON DELETE CASCADE,
  creditor_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  obligation_type TEXT NOT NULL,
  source_id TEXT NOT NULL,
  priority SMALLINT NOT NULL,
  amount_units BIGINT NOT NULL CHECK (amount_units >= 0),
  paid_units BIGINT NOT NULL DEFAULT 0 CHECK (paid_units >= 0 AND paid_units <= amount_units),
  status TEXT NOT NULL DEFAULT 'DUE' CHECK (status IN ('DUE','PARTIAL','PAID','WRITTEN_OFF')),
  UNIQUE (proceeding_id, obligation_type, source_id)
);

CREATE INDEX IF NOT EXISTS corporation_insolvency_status_idx ON corporation_insolvency_proceedings(status, opened_game_day);
CREATE INDEX IF NOT EXISTS corporation_claims_priority_idx ON corporation_creditor_claims(proceeding_id, priority, id);

CREATE OR REPLACE FUNCTION earth_open_corporation_insolvency(p_institution_id TEXT, p_game_day BIGINT, p_correlation_id TEXT)
RETURNS corporation_insolvency_proceedings LANGUAGE plpgsql AS $$
DECLARE result corporation_insolvency_proceedings; owner_row RECORD; metrics RECORD;
BEGIN
  SELECT * INTO result FROM corporation_insolvency_proceedings WHERE correlation_id = p_correlation_id;
  IF FOUND THEN RETURN result; END IF;
  SELECT o.economic_id INTO owner_row FROM institutions i JOIN owner_registry o ON o.id = i.id
   WHERE i.id = p_institution_id AND i.kind = 'CORPORATION' AND i.status = 'active' AND o.status = 'active' FOR UPDATE;
  IF owner_row.economic_id IS NULL THEN RAISE EXCEPTION 'Corporate debtor is unavailable'; END IF;
  SELECT * INTO metrics FROM earth_personal_insolvency_metrics(owner_row.economic_id, p_game_day);
  IF metrics.serviceable OR NOT metrics.materially_insolvent THEN RAISE EXCEPTION 'Corporate insolvency criteria are not met'; END IF;
  INSERT INTO corporation_insolvency_proceedings (institution_id, debtor_economic_id, status, opened_game_day, liabilities_units, estate_value_units, correlation_id)
    VALUES (p_institution_id, owner_row.economic_id, 'RESTRUCTURING', p_game_day, metrics.liabilities_units, metrics.realizable_assets_units, p_correlation_id)
    RETURNING * INTO result;
  INSERT INTO financial_states (institution_id, institution_kind, status, since_game_day, last_reason)
    VALUES (p_institution_id, 'CORPORATION', 'restructuring', p_game_day, 'V2 corporate insolvency proceeding opened')
    ON CONFLICT (institution_id) DO UPDATE SET status = 'restructuring', since_game_day = p_game_day, last_reason = EXCLUDED.last_reason, updated_at = CURRENT_TIMESTAMP;
  INSERT INTO corporation_estate_assets (proceeding_id, account_id, asset_id, asset_units, liquidation_value_units, source_kind, source_id)
    SELECT result.id, a.id, a.asset_id, a.balance, a.balance, 'economic_account', a.id::TEXT
      FROM economic_accounts a WHERE a.owner_economic_id = owner_row.economic_id AND a.status = 'active' AND a.account_type NOT IN (7,8)
    ON CONFLICT DO NOTHING;
  INSERT INTO corporation_creditor_claims (proceeding_id, creditor_economic_id, obligation_type, source_id, priority, amount_units)
    SELECT result.id, f.creditor_economic_id, f.obligation_type, f.source_id, f.priority_class, f.principal_due_units + f.interest_due_units
      FROM financial_obligations f WHERE f.debtor_economic_id = owner_row.economic_id
    ON CONFLICT DO NOTHING;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION earth_reject_distressed_corporation_loan()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM institutions i JOIN financial_states s ON s.institution_id = i.id
    JOIN owner_registry o ON o.id = i.id
    WHERE o.economic_id = NEW.borrower_economic_id AND i.kind = 'CORPORATION'
      AND s.status IN ('distressed','restructuring','insolvent','liquidation')) THEN
    RAISE EXCEPTION 'Distressed corporation cannot originate a new loan';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS bank_loans_reject_distressed_corporation ON bank_loans;
CREATE TRIGGER bank_loans_reject_distressed_corporation BEFORE INSERT ON bank_loans FOR EACH ROW EXECUTE FUNCTION earth_reject_distressed_corporation_loan();
