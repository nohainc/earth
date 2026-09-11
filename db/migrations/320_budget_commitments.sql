-- Cities, Corporations & Budgets V2 Plan 6.
-- Commitments reserve budget authority until paid, cancelled, or expired.

CREATE TABLE institution_budget_commitments (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  institution_id TEXT NOT NULL REFERENCES institutions(id),
  budget_line_id BIGINT NOT NULL REFERENCES institution_budget_lines(id),
  commitment_type TEXT NOT NULL CHECK (commitment_type IN ('CONSTRUCTION_PROJECT', 'TECHNOLOGY_LICENSE', 'RESEARCH_PROJECT', 'PUBLIC_SERVICE_CONTRACT', 'GRANT', 'LOAN_PAYMENT')),
  source_type TEXT NOT NULL,
  source_id TEXT NOT NULL,
  original_units BIGINT NOT NULL CHECK (original_units > 0),
  remaining_units BIGINT NOT NULL CHECK (remaining_units >= 0 AND remaining_units <= original_units),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'PARTIALLY_PAID', 'SETTLED', 'CANCELLED', 'EXPIRED')),
  created_game_day BIGINT NOT NULL CHECK (created_game_day >= 1),
  due_game_day BIGINT NOT NULL CHECK (due_game_day >= created_game_day),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (budget_line_id, commitment_type, source_type, source_id)
);

CREATE INDEX institution_budget_commitments_due_idx
  ON institution_budget_commitments (status, due_game_day, institution_id);
CREATE INDEX institution_budget_commitments_line_idx
  ON institution_budget_commitments (budget_line_id, status);

CREATE OR REPLACE FUNCTION earth_reserve_budget_commitment()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  available_units BIGINT;
  line_institution_id TEXT;
BEGIN
  SELECT institution_id, authorized_units - committed_units - spent_units
    INTO line_institution_id, available_units
    FROM institution_budget_lines
   WHERE id = NEW.budget_line_id
   FOR UPDATE;
  IF line_institution_id IS NULL THEN
    RAISE EXCEPTION 'Budget line % does not exist', NEW.budget_line_id;
  END IF;
  IF line_institution_id <> NEW.institution_id THEN
    RAISE EXCEPTION 'Commitment institution does not match budget line';
  END IF;
  IF NEW.remaining_units <> NEW.original_units THEN
    RAISE EXCEPTION 'New budget commitment must start fully outstanding';
  END IF;
  IF NEW.original_units > available_units THEN
    RAISE EXCEPTION 'Budget commitment exceeds available authority on line %', NEW.budget_line_id;
  END IF;
  UPDATE institution_budget_lines
     SET committed_units = committed_units + NEW.original_units,
         updated_at = CURRENT_TIMESTAMP
   WHERE id = NEW.budget_line_id;
  RETURN NEW;
END;
$$;

CREATE TRIGGER institution_budget_commitments_reserve_trigger
AFTER INSERT ON institution_budget_commitments
FOR EACH ROW EXECUTE FUNCTION earth_reserve_budget_commitment();

CREATE OR REPLACE FUNCTION earth_create_budget_commitment(
  p_institution_id TEXT,
  p_budget_line_id BIGINT,
  p_commitment_type TEXT,
  p_source_type TEXT,
  p_source_id TEXT,
  p_original_units BIGINT,
  p_created_game_day BIGINT,
  p_due_game_day BIGINT
)
RETURNS BIGINT
LANGUAGE SQL
AS $$
  INSERT INTO institution_budget_commitments (
    institution_id, budget_line_id, commitment_type, source_type, source_id,
    original_units, remaining_units, created_game_day, due_game_day
  ) VALUES (
    p_institution_id, p_budget_line_id, p_commitment_type, p_source_type, p_source_id,
    p_original_units, p_original_units, p_created_game_day, p_due_game_day
  )
  ON CONFLICT (budget_line_id, commitment_type, source_type, source_id)
  DO UPDATE SET updated_at = CURRENT_TIMESTAMP
  RETURNING id;
$$;

CREATE OR REPLACE FUNCTION earth_pay_budget_commitment(
  p_commitment_id BIGINT,
  p_payment_units BIGINT
)
RETURNS TABLE (commitment_id BIGINT, paid_units BIGINT, remaining_units BIGINT)
LANGUAGE plpgsql
AS $$
DECLARE
  commitment_row institution_budget_commitments%ROWTYPE;
BEGIN
  IF p_payment_units <= 0 THEN
    RAISE EXCEPTION 'Budget commitment payment must be positive';
  END IF;
  SELECT * INTO commitment_row
    FROM institution_budget_commitments
   WHERE id = p_commitment_id
   FOR UPDATE;
  IF commitment_row.id IS NULL OR commitment_row.status NOT IN ('ACTIVE', 'PARTIALLY_PAID') THEN
    RAISE EXCEPTION 'Budget commitment % is not payable', p_commitment_id;
  END IF;
  IF p_payment_units > commitment_row.remaining_units THEN
    RAISE EXCEPTION 'Payment exceeds remaining budget commitment %', p_commitment_id;
  END IF;
  UPDATE institution_budget_lines
     SET committed_units = committed_units - p_payment_units,
         spent_units = spent_units + p_payment_units,
         updated_at = CURRENT_TIMESTAMP
   WHERE id = commitment_row.budget_line_id;
  UPDATE institution_budget_commitments
     SET remaining_units = remaining_units - p_payment_units,
         status = CASE WHEN remaining_units - p_payment_units = 0 THEN 'SETTLED' ELSE 'PARTIALLY_PAID' END,
         updated_at = CURRENT_TIMESTAMP
   WHERE id = p_commitment_id;
  RETURN QUERY SELECT p_commitment_id, p_payment_units, commitment_row.remaining_units - p_payment_units;
END;
$$;

CREATE OR REPLACE FUNCTION earth_cancel_budget_commitment(p_commitment_id BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
  commitment_row institution_budget_commitments%ROWTYPE;
BEGIN
  SELECT * INTO commitment_row
    FROM institution_budget_commitments
   WHERE id = p_commitment_id
   FOR UPDATE;
  IF commitment_row.id IS NULL OR commitment_row.status NOT IN ('ACTIVE', 'PARTIALLY_PAID') THEN
    RETURN 0;
  END IF;
  UPDATE institution_budget_lines
     SET committed_units = committed_units - commitment_row.remaining_units,
         updated_at = CURRENT_TIMESTAMP
   WHERE id = commitment_row.budget_line_id;
  UPDATE institution_budget_commitments
     SET remaining_units = 0, status = 'CANCELLED', updated_at = CURRENT_TIMESTAMP
   WHERE id = p_commitment_id;
  RETURN commitment_row.remaining_units;
END;
$$;

COMMENT ON TABLE institution_budget_commitments IS
  'Outstanding institutional spending obligations reserving budget-line authority until payment or release.';
