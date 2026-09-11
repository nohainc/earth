-- Cities, Corporations & Budgets V2 Plan 15.

ALTER TABLE budget_categories ADD COLUMN IF NOT EXISTS spending_class TEXT;
UPDATE budget_categories SET spending_class = CASE WHEN mandatory THEN 'MANDATORY' ELSE 'DISCRETIONARY' END WHERE spending_class IS NULL;
ALTER TABLE budget_categories
  ALTER COLUMN spending_class SET NOT NULL,
  ALTER COLUMN spending_class SET DEFAULT 'DISCRETIONARY',
  ADD CONSTRAINT budget_categories_spending_class_ck CHECK (spending_class IN ('MANDATORY', 'DISCRETIONARY'));
