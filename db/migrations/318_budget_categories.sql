-- Cities, Corporations & Budgets V2 Plan 4.
-- Budget categories are a governed vocabulary, not free-form strings.

CREATE TABLE IF NOT EXISTS budget_categories (
  institution_kind TEXT NOT NULL CHECK (institution_kind IN ('CITY', 'CORPORATION', 'OUC', 'GLOBAL_BANK')),
  category_code TEXT NOT NULL CHECK (category_code = UPPER(category_code)),
  mandatory BOOLEAN NOT NULL DEFAULT FALSE,
  priority SMALLINT NOT NULL DEFAULT 100 CHECK (priority >= 0),
  rules JSONB NOT NULL DEFAULT '{}'::JSONB,
  PRIMARY KEY (institution_kind, category_code)
);

INSERT INTO budget_categories (institution_kind, category_code, mandatory, priority)
VALUES
  ('CITY', 'ESSENTIAL_SERVICES', TRUE, 10), ('CITY', 'INFRASTRUCTURE', FALSE, 30),
  ('CITY', 'HEALTH', TRUE, 20), ('CITY', 'ENERGY', TRUE, 20),
  ('CITY', 'CONNECTIVITY', TRUE, 20), ('CITY', 'HOUSING', TRUE, 20),
  ('CITY', 'RESEARCH', FALSE, 70), ('CITY', 'PUBLIC_SAFETY', FALSE, 40),
  ('CITY', 'TRANSFERS', FALSE, 80), ('CITY', 'DEBT_SERVICE', TRUE, 5),
  ('CITY', 'EMERGENCY', FALSE, 1),
  ('CORPORATION', 'OPERATIONS', TRUE, 20), ('CORPORATION', 'CAPEX', FALSE, 40),
  ('CORPORATION', 'RESEARCH', FALSE, 60), ('CORPORATION', 'LICENSING', FALSE, 70),
  ('CORPORATION', 'EXPANSION', FALSE, 80), ('CORPORATION', 'CITY_SUPPORT', FALSE, 50),
  ('CORPORATION', 'DEBT_SERVICE', TRUE, 5), ('CORPORATION', 'DIVIDENDS', FALSE, 90),
  ('CORPORATION', 'RESERVE_ALLOCATION', TRUE, 10)
ON CONFLICT (institution_kind, category_code) DO UPDATE
SET mandatory = EXCLUDED.mandatory, priority = EXCLUDED.priority;

ALTER TABLE institution_budget_lines
  ADD COLUMN IF NOT EXISTS institution_kind TEXT,
  ADD COLUMN IF NOT EXISTS category_code TEXT;

UPDATE institution_budget_lines b
SET institution_kind = i.kind,
    category_code = CASE LOWER(b.category)
      WHEN 'housing' THEN 'HOUSING'
      WHEN 'energy' THEN 'ENERGY'
      WHEN 'connectivity' THEN 'CONNECTIVITY'
      WHEN 'health' THEN 'HEALTH'
      WHEN 'infrastructure' THEN 'INFRASTRUCTURE'
      WHEN 'public-services' THEN 'ESSENTIAL_SERVICES'
      WHEN 'maintenance' THEN 'ESSENTIAL_SERVICES'
      ELSE UPPER(REPLACE(b.category, '-', '_'))
    END
FROM institutions i
WHERE i.id = b.institution_id;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM institution_budget_lines
    WHERE institution_kind IS NULL OR category_code IS NULL
  ) THEN
    RAISE EXCEPTION 'Cannot classify every institution budget line';
  END IF;
  IF EXISTS (
    SELECT 1 FROM institution_budget_lines b
    LEFT JOIN budget_categories c
      ON c.institution_kind = b.institution_kind
     AND c.category_code = b.category_code
    WHERE c.category_code IS NULL
  ) THEN
    RAISE EXCEPTION 'Institution budget line uses an undefined category';
  END IF;
END;
$$;

ALTER TABLE institution_budget_lines
  DROP CONSTRAINT IF EXISTS institution_budget_lines_category_fk,
  DROP CONSTRAINT IF EXISTS institution_budget_lines_institution_kind_ck;
ALTER TABLE institution_budget_lines
  DROP COLUMN category,
  ALTER COLUMN institution_kind SET NOT NULL,
  ALTER COLUMN category_code SET NOT NULL;
ALTER TABLE institution_budget_lines
  ADD CONSTRAINT institution_budget_lines_category_fk
    FOREIGN KEY (institution_kind, category_code)
    REFERENCES budget_categories(institution_kind, category_code),
  ADD CONSTRAINT institution_budget_lines_institution_kind_ck
    CHECK (institution_kind IN ('CITY', 'CORPORATION', 'OUC', 'GLOBAL_BANK'));

CREATE OR REPLACE FUNCTION earth_validate_budget_line_institution_kind()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE v_kind TEXT;
BEGIN
  SELECT kind INTO v_kind FROM institutions WHERE id = NEW.institution_id;
  IF v_kind IS NULL OR v_kind <> NEW.institution_kind THEN
    RAISE EXCEPTION 'Budget line institution kind does not match institution %', NEW.institution_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS institution_budget_lines_kind_trigger ON institution_budget_lines;
CREATE TRIGGER institution_budget_lines_kind_trigger
BEFORE INSERT OR UPDATE OF institution_id, institution_kind ON institution_budget_lines
FOR EACH ROW EXECUTE FUNCTION earth_validate_budget_line_institution_kind();
