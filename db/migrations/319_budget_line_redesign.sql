-- Cities, Corporations & Budgets V2 Plan 5.
-- Budget lines have stable identities and distinguish outstanding commitments
-- from amounts already spent.

ALTER TABLE budget_categories
  ADD COLUMN IF NOT EXISTS id BIGINT GENERATED ALWAYS AS IDENTITY;
ALTER TABLE budget_categories
  DROP CONSTRAINT IF EXISTS budget_categories_pkey;
ALTER TABLE budget_categories
  ADD CONSTRAINT budget_categories_pkey PRIMARY KEY (id);
ALTER TABLE budget_categories
  ADD CONSTRAINT budget_categories_kind_code_uq UNIQUE (institution_kind, category_code);

ALTER TABLE institution_budget_lines
  ADD COLUMN IF NOT EXISTS id BIGINT GENERATED ALWAYS AS IDENTITY,
  ADD COLUMN IF NOT EXISTS category_id BIGINT,
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'ACTIVE',
  ADD COLUMN IF NOT EXISTS created_game_day BIGINT;

UPDATE institution_budget_lines b
SET category_id = c.id,
    status = COALESCE(NULLIF(b.status, ''), 'ACTIVE'),
    created_game_day = COALESCE(b.created_game_day, p.start_game_day)
FROM budget_categories c, fiscal_periods p
WHERE c.institution_kind = b.institution_kind
  AND c.category_code = b.category_code
  AND p.id = b.fiscal_period_id;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM institution_budget_lines WHERE category_id IS NULL OR created_game_day IS NULL) THEN
    RAISE EXCEPTION 'Cannot complete budget line redesign with missing category or creation day';
  END IF;
END;
$$;

-- The original table had table-level checks such as committed_units >= spent_units.
-- They encode a different meaning for commitments and must not survive the cutover.
DO $$
DECLARE constraint_row RECORD;
BEGIN
  FOR constraint_row IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'institution_budget_lines'::regclass
      AND contype = 'c'
  LOOP
    EXECUTE format('ALTER TABLE institution_budget_lines DROP CONSTRAINT %I', constraint_row.conname);
  END LOOP;
END;
$$;

ALTER TABLE institution_budget_lines
  DROP CONSTRAINT IF EXISTS institution_budget_lines_pkey,
  DROP CONSTRAINT IF EXISTS institution_budget_lines_category_fk,
  DROP CONSTRAINT IF EXISTS institution_budget_lines_institution_kind_ck,
  DROP COLUMN institution_kind,
  DROP COLUMN category_code,
  DROP COLUMN IF EXISTS category,
  ALTER COLUMN id SET NOT NULL,
  ALTER COLUMN category_id SET NOT NULL,
  ALTER COLUMN created_game_day SET NOT NULL;

ALTER TABLE institution_budget_lines
  ADD CONSTRAINT institution_budget_lines_pkey PRIMARY KEY (id),
  ADD CONSTRAINT institution_budget_lines_category_fk
    FOREIGN KEY (category_id) REFERENCES budget_categories(id),
  ADD CONSTRAINT institution_budget_lines_status_ck
    CHECK (status IN ('DRAFT', 'ACTIVE', 'CLOSED', 'CANCELLED')),
  ADD CONSTRAINT institution_budget_lines_authority_ck
    CHECK (authorized_units >= committed_units + spent_units),
  ADD CONSTRAINT institution_budget_lines_spent_ck
    CHECK (spent_units >= 0 AND committed_units >= 0);

CREATE UNIQUE INDEX institution_budget_lines_scope_uq
  ON institution_budget_lines (institution_id, fiscal_period_id, category_id);

CREATE OR REPLACE FUNCTION earth_validate_budget_line_institution_kind()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE v_institution_kind TEXT; v_category_kind TEXT;
BEGIN
  SELECT kind INTO v_institution_kind FROM institutions WHERE id = NEW.institution_id;
  SELECT institution_kind INTO v_category_kind FROM budget_categories WHERE id = NEW.category_id;
  IF v_institution_kind IS NULL OR v_category_kind IS NULL OR v_institution_kind <> v_category_kind THEN
    RAISE EXCEPTION 'Budget line category does not match institution %', NEW.institution_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS institution_budget_lines_kind_trigger ON institution_budget_lines;
CREATE TRIGGER institution_budget_lines_kind_trigger
BEFORE INSERT OR UPDATE OF institution_id, category_id ON institution_budget_lines
FOR EACH ROW EXECUTE FUNCTION earth_validate_budget_line_institution_kind();

COMMENT ON TABLE institution_budget_lines IS
  'Institutional budget authorizations with stable IDs; committed_units are outstanding commitments and spent_units are paid amounts.';
