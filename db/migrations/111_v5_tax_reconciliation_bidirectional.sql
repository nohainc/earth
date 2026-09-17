-- EARTH ACTIVE MIGRATION: make tax shadow reconciliation bidirectional.
-- A clean comparison requires evidence for canonical rules that are absent from
-- the legacy bridge as well as legacy rules absent from Constitution snapshots.

ALTER TABLE v5_tax_reconciliation_items
  ALTER COLUMN legacy_rate_bps DROP NOT NULL;

ALTER TABLE v5_tax_reconciliation_runs
  ADD COLUMN IF NOT EXISTS missing_legacy INTEGER NOT NULL DEFAULT 0
  CHECK (missing_legacy >= 0);

ALTER TABLE v5_tax_reconciliation_items
  DROP CONSTRAINT IF EXISTS v5_tax_reconciliation_items_result_check;

ALTER TABLE v5_tax_reconciliation_items
  ADD CONSTRAINT v5_tax_reconciliation_items_result_check
  CHECK (result IN ('MATCH', 'MISMATCH', 'MISSING_CANONICAL', 'MISSING_LEGACY'));
