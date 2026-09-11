-- Cities, Corporations & Budgets V2 Plan 28.
-- Preserve budget authorization during crisis; freeze only discretionary lines.

ALTER TABLE institution_budget_lines
  DROP CONSTRAINT IF EXISTS institution_budget_lines_status_check;
ALTER TABLE institution_budget_lines
  ADD CONSTRAINT institution_budget_lines_status_check
  CHECK (status IN ('DRAFT', 'ACTIVE', 'FROZEN', 'CLOSED', 'CANCELLED'));

ALTER TABLE institution_budget_commitments
  ADD COLUMN IF NOT EXISTS priority_class SMALLINT NOT NULL DEFAULT 100
  CHECK (priority_class >= 0);

UPDATE institution_budget_commitments c
   SET priority_class = COALESCE(bc.priority, 100)
  FROM institution_budget_lines l
  JOIN budget_categories bc ON bc.id = l.category_id
 WHERE c.budget_line_id = l.id;

CREATE OR REPLACE FUNCTION earth_apply_financial_budget_policy(p_institution_id TEXT, p_status TEXT)
RETURNS VOID
LANGUAGE SQL
AS $$
  UPDATE institution_budget_lines l
     SET status = CASE
       WHEN c.spending_class = 'DISCRETIONARY'
        AND lower(p_status) IN ('distressed','fiscal_stress','receivership','restructuring','insolvent','liquidation','recovery')
         THEN 'FROZEN'
       WHEN c.spending_class = 'MANDATORY' AND l.status = 'FROZEN'
         THEN 'ACTIVE'
       ELSE l.status
     END,
     updated_at = CURRENT_TIMESTAMP
    FROM budget_categories c
   WHERE l.category_id = c.id AND l.institution_id = p_institution_id;
$$;

CREATE OR REPLACE FUNCTION earth_financial_state_budget_policy()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status THEN
    PERFORM earth_apply_financial_budget_policy(NEW.institution_id, NEW.status);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS financial_states_budget_policy_trigger ON financial_states;
CREATE TRIGGER financial_states_budget_policy_trigger
AFTER INSERT OR UPDATE OF status ON financial_states
FOR EACH ROW EXECUTE FUNCTION earth_financial_state_budget_policy();

SELECT earth_apply_financial_budget_policy(institution_id, status) FROM financial_states;

CREATE OR REPLACE FUNCTION earth_set_budget_commitment_priority()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  SELECT c.priority INTO NEW.priority_class
    FROM institution_budget_lines l JOIN budget_categories c ON c.id = l.category_id
   WHERE l.id = NEW.budget_line_id;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS institution_budget_commitment_priority_trigger ON institution_budget_commitments;
CREATE TRIGGER institution_budget_commitment_priority_trigger
BEFORE INSERT OR UPDATE OF budget_line_id ON institution_budget_commitments
FOR EACH ROW EXECUTE FUNCTION earth_set_budget_commitment_priority();
