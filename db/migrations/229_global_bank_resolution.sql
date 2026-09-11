-- Finance V2 Plan 19: explicit Global Bank distress and resolution states.

ALTER TABLE global_bank_balance_sheet DROP CONSTRAINT IF EXISTS global_bank_balance_sheet_status_check;
ALTER TABLE global_bank_balance_sheet ADD CONSTRAINT global_bank_balance_sheet_status_check
  CHECK (status IN ('healthy', 'illiquid', 'liquidity_stress', 'undercapitalized', 'insolvent', 'resolution'));

CREATE TABLE IF NOT EXISTS global_bank_resolution_state (
  id SMALLINT PRIMARY KEY CHECK (id = 1),
  status TEXT NOT NULL CHECK (status IN ('NORMAL','LIQUIDITY_STRESS','UNDERCAPITALIZED','INSOLVENT','RESOLUTION')),
  as_of_game_day BIGINT NOT NULL,
  reason TEXT NOT NULL DEFAULT '',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS global_bank_resolution_events (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  game_day BIGINT NOT NULL,
  from_status TEXT,
  to_status TEXT NOT NULL,
  action TEXT NOT NULL,
  amount_units BIGINT NOT NULL DEFAULT 0,
  economic_transaction_id BIGINT,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION earth_evaluate_global_bank_resolution(p_game_day BIGINT)
RETURNS global_bank_resolution_state LANGUAGE plpgsql AS $$
DECLARE sheet global_bank_balance_sheet; result global_bank_resolution_state; next_status TEXT; reason TEXT;
BEGIN
  SELECT * INTO sheet FROM earth_refresh_global_bank_balance_sheet(p_game_day);
  next_status := CASE sheet.status
    WHEN 'illiquid' THEN 'LIQUIDITY_STRESS'
    WHEN 'liquidity_stress' THEN 'LIQUIDITY_STRESS'
    WHEN 'undercapitalized' THEN 'UNDERCAPITALIZED'
    WHEN 'insolvent' THEN 'INSOLVENT'
    ELSE 'NORMAL' END;
  reason := CASE next_status
    WHEN 'LIQUIDITY_STRESS' THEN 'Reserve liquidity is below current liabilities'
    WHEN 'UNDERCAPITALIZED' THEN 'Bank equity is below the configured capital threshold'
    WHEN 'INSOLVENT' THEN 'Bank assets are below recorded liabilities'
    ELSE 'Bank balance sheet is within configured limits' END;
  INSERT INTO global_bank_resolution_state (id, status, as_of_game_day, reason)
    VALUES (1, next_status, p_game_day, reason)
    ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status, as_of_game_day = EXCLUDED.as_of_game_day, reason = EXCLUDED.reason, updated_at = CURRENT_TIMESTAMP
    RETURNING * INTO result;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION earth_reject_loan_when_bank_stressed()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM global_bank_resolution_state WHERE id = 1 AND status IN ('LIQUIDITY_STRESS','UNDERCAPITALIZED','INSOLVENT','RESOLUTION')) THEN
    RAISE EXCEPTION 'Global Bank is not accepting new lending while under financial stress';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS bank_loans_reject_stressed_bank ON bank_loans;
CREATE TRIGGER bank_loans_reject_stressed_bank BEFORE INSERT ON bank_loans FOR EACH ROW EXECUTE FUNCTION earth_reject_loan_when_bank_stressed();
