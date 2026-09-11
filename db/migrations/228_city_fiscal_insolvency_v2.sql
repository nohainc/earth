-- Finance V2 Plan 18: cities use fiscal stress and receivership, not liquidation.

ALTER TABLE financial_states DROP CONSTRAINT IF EXISTS financial_states_status_check;
ALTER TABLE financial_states ADD CONSTRAINT financial_states_status_check
  CHECK (status IN ('active','distressed','fiscal_stress','receivership','recovery','restructuring','insolvent','liquidation','bankrupt','dissolved'));

CREATE TABLE IF NOT EXISTS city_fiscal_proceedings (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  city_id TEXT NOT NULL REFERENCES cities(id),
  debtor_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  status TEXT NOT NULL CHECK (status IN ('FISCAL_STRESS','RECEIVERSHIP','RECOVERY','ACTIVE','FAILED')),
  opened_game_day BIGINT NOT NULL,
  recovery_game_day BIGINT,
  resolved_game_day BIGINT,
  due_obligations_units BIGINT NOT NULL DEFAULT 0,
  treasury_units BIGINT NOT NULL DEFAULT 0,
  recovery_plan JSONB NOT NULL DEFAULT '{}'::JSONB,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (city_id, status)
);
CREATE INDEX IF NOT EXISTS city_fiscal_proceedings_status_idx ON city_fiscal_proceedings(status, opened_game_day);

CREATE OR REPLACE FUNCTION earth_open_city_receivership(p_city_id TEXT, p_game_day BIGINT, p_correlation_id TEXT)
RETURNS city_fiscal_proceedings LANGUAGE plpgsql AS $$
DECLARE result city_fiscal_proceedings; owner_row RECORD; metrics RECORD; treasury BIGINT;
BEGIN
  SELECT * INTO result FROM city_fiscal_proceedings WHERE correlation_id = p_correlation_id;
  IF FOUND THEN RETURN result; END IF;
  SELECT o.economic_id INTO owner_row FROM cities c JOIN owner_registry o ON o.id = c.id
    WHERE c.id = p_city_id AND c.status = 'active' AND o.owner_type = 'city' AND o.status = 'active' FOR UPDATE;
  IF owner_row.economic_id IS NULL THEN RAISE EXCEPTION 'City fiscal debtor is unavailable'; END IF;
  SELECT * INTO metrics FROM earth_personal_insolvency_metrics(owner_row.economic_id, p_game_day);
  SELECT COALESCE(SUM(balance), 0)::BIGINT INTO treasury FROM economic_accounts
    WHERE owner_economic_id = owner_row.economic_id AND asset_id = 1 AND account_type = 3 AND status = 'active';
  IF metrics.serviceable OR treasury > 0 THEN RAISE EXCEPTION 'City fiscal stress criteria are not met'; END IF;
  INSERT INTO city_fiscal_proceedings (city_id, debtor_economic_id, status, opened_game_day, due_obligations_units, treasury_units, recovery_plan, correlation_id)
    VALUES (p_city_id, owner_row.economic_id, 'RECEIVERSHIP', p_game_day, metrics.due_units, treasury,
      '{"nonessential_spending":false,"dividends":false,"new_debt":false,"essential_services":true}'::JSONB, p_correlation_id)
    RETURNING * INTO result;
  INSERT INTO financial_states (institution_id, institution_kind, status, since_game_day, last_reason)
    VALUES (p_city_id, 'CITY', 'receivership', p_game_day, 'V2 city fiscal receivership opened')
    ON CONFLICT (institution_id) DO UPDATE SET status = 'receivership', since_game_day = p_game_day, last_reason = EXCLUDED.last_reason, updated_at = CURRENT_TIMESTAMP;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION earth_reject_receivership_city_loan()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM institutions i JOIN financial_states s ON s.institution_id = i.id
    JOIN owner_registry o ON o.id = i.id
    WHERE o.economic_id = NEW.borrower_economic_id AND i.kind = 'CITY'
      AND s.status IN ('fiscal_stress','receivership')) THEN
    RAISE EXCEPTION 'City in fiscal receivership cannot originate a new loan';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS bank_loans_reject_receivership_city ON bank_loans;
CREATE TRIGGER bank_loans_reject_receivership_city BEFORE INSERT ON bank_loans FOR EACH ROW EXECUTE FUNCTION earth_reject_receivership_city_loan();
