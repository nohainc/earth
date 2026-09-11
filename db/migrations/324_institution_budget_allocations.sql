-- Cities, Corporations & Budgets V2 Plan 11.
-- Parent appropriations are authority; funded_units are actual transfers.

CREATE TABLE institution_budget_allocations (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  parent_institution_id TEXT NOT NULL REFERENCES institutions(id),
  child_institution_id TEXT NOT NULL REFERENCES institutions(id),
  parent_budget_line_id BIGINT NOT NULL REFERENCES institution_budget_lines(id),
  child_budget_line_id BIGINT NOT NULL REFERENCES institution_budget_lines(id),
  fiscal_period_id BIGINT NOT NULL REFERENCES fiscal_periods(id),
  category_id BIGINT NOT NULL REFERENCES budget_categories(id),
  authorized_units BIGINT NOT NULL CHECK (authorized_units >= 0),
  funded_units BIGINT NOT NULL DEFAULT 0 CHECK (funded_units >= 0),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('DRAFT', 'ACTIVE', 'CLOSED', 'CANCELLED')),
  rule_version TEXT NOT NULL,
  created_game_day BIGINT NOT NULL CHECK (created_game_day >= 1),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (parent_institution_id, child_institution_id, fiscal_period_id, category_id),
  CHECK (parent_institution_id <> child_institution_id),
  CHECK (funded_units <= authorized_units)
);

CREATE INDEX institution_budget_allocations_child_idx ON institution_budget_allocations (child_institution_id, fiscal_period_id, category_id);

CREATE OR REPLACE FUNCTION earth_set_budget_allocation(
  p_parent_institution_id TEXT, p_child_institution_id TEXT, p_parent_budget_line_id BIGINT,
  p_child_budget_line_id BIGINT, p_fiscal_period_id BIGINT, p_category_id BIGINT,
  p_authorized_units BIGINT, p_created_game_day BIGINT, p_rule_version TEXT
)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE parent_line institution_budget_lines%ROWTYPE; child_line institution_budget_lines%ROWTYPE; existing_units BIGINT;
BEGIN
  SELECT * INTO parent_line FROM institution_budget_lines WHERE id = p_parent_budget_line_id FOR UPDATE;
  SELECT * INTO child_line FROM institution_budget_lines WHERE id = p_child_budget_line_id FOR UPDATE;
  IF parent_line.id IS NULL OR child_line.id IS NULL OR parent_line.institution_id <> p_parent_institution_id OR child_line.institution_id <> p_child_institution_id OR parent_line.fiscal_period_id <> p_fiscal_period_id OR child_line.fiscal_period_id <> p_fiscal_period_id THEN
    RAISE EXCEPTION 'Budget allocation lines do not match the requested institutions and period';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM institutions WHERE id = p_parent_institution_id AND kind = 'CORPORATION') OR NOT EXISTS (SELECT 1 FROM institutions i JOIN cities c ON c.id = i.id WHERE i.id = p_child_institution_id AND i.kind = 'CITY' AND c.corporation_id = p_parent_institution_id) THEN
    RAISE EXCEPTION 'Budget allocation must connect a corporation to one of its cities';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM budget_categories WHERE id = parent_line.category_id AND institution_kind = 'CORPORATION' AND category_code = 'CITY_SUPPORT') THEN
    RAISE EXCEPTION 'Parent allocation line must be CORPORATION CITY_SUPPORT';
  END IF;
  IF p_authorized_units < 0 THEN RAISE EXCEPTION 'Allocation authority cannot be negative'; END IF;
  SELECT COALESCE(SUM(authorized_units), 0) INTO existing_units
    FROM institution_budget_allocations
   WHERE parent_budget_line_id = p_parent_budget_line_id
     AND id <> COALESCE((SELECT id FROM institution_budget_allocations WHERE parent_institution_id = p_parent_institution_id AND child_institution_id = p_child_institution_id AND fiscal_period_id = p_fiscal_period_id AND category_id = p_category_id), 0)
     AND status IN ('DRAFT', 'ACTIVE');
  IF existing_units + p_authorized_units > parent_line.authorized_units - parent_line.committed_units - parent_line.spent_units THEN
    RAISE EXCEPTION 'Child allocations exceed the corporation CITY_SUPPORT envelope';
  END IF;
  INSERT INTO institution_budget_allocations (parent_institution_id, child_institution_id, parent_budget_line_id, child_budget_line_id, fiscal_period_id, category_id, authorized_units, created_game_day, rule_version)
  VALUES (p_parent_institution_id, p_child_institution_id, p_parent_budget_line_id, p_child_budget_line_id, p_fiscal_period_id, p_category_id, p_authorized_units, p_created_game_day, p_rule_version)
  ON CONFLICT (parent_institution_id, child_institution_id, fiscal_period_id, category_id)
  DO UPDATE SET authorized_units = EXCLUDED.authorized_units, updated_at = CURRENT_TIMESTAMP, rule_version = EXCLUDED.rule_version
  RETURNING id;
  RETURN (SELECT id FROM institution_budget_allocations WHERE parent_institution_id = p_parent_institution_id AND child_institution_id = p_child_institution_id AND fiscal_period_id = p_fiscal_period_id AND category_id = p_category_id);
END;
$$;
