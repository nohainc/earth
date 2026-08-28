-- The active Earth tax rules are the authoritative live values for the
-- Constitution's Revenue rules.  Existing live values are never overwritten.
INSERT INTO tax_rules (id, scope, category, rate, active, version)
VALUES
  ('TAX-OUC-BASIC', 'global', 'basic_income', 0.020000, true, 1),
  ('TAX-OUC-BUSINESS', 'global', 'business', 0.050000, true, 1),
  ('TAX-OUC-MARKET', 'global', 'market', 0.010000, true, 1)
ON CONFLICT (id) DO NOTHING;

-- Implementation delay belongs to the active governance rule, alongside its
-- quorum and approval threshold. Existing rules receive the persisted value.
ALTER TABLE governance_rules
  ADD COLUMN IF NOT EXISTS implementation_delay_days integer NOT NULL DEFAULT 1
  CHECK (implementation_delay_days >= 0 AND implementation_delay_days <= 30);
