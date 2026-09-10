-- Economy V2 Plan 13: cumulative economic projections.
-- Domain-specific snapshots remain untouched. These totals eliminate repeated
-- full-ledger SUM scans for owner-level historical summaries.

CREATE TABLE IF NOT EXISTS economic_owner_totals (
  owner_economic_id BIGINT PRIMARY KEY REFERENCES owner_registry(economic_id),
  credit_received BIGINT NOT NULL DEFAULT 0,
  credit_spent BIGINT NOT NULL DEFAULT 0,
  material_received BIGINT NOT NULL DEFAULT 0,
  material_spent BIGINT NOT NULL DEFAULT 0,
  components_received BIGINT NOT NULL DEFAULT 0,
  components_spent BIGINT NOT NULL DEFAULT 0,
  energy_received BIGINT NOT NULL DEFAULT 0,
  energy_spent BIGINT NOT NULL DEFAULT 0,
  compute_received BIGINT NOT NULL DEFAULT 0,
  compute_spent BIGINT NOT NULL DEFAULT 0,
  food_received BIGINT NOT NULL DEFAULT 0,
  food_spent BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO economic_owner_totals (owner_economic_id)
SELECT economic_id FROM owner_registry
ON CONFLICT (owner_economic_id) DO NOTHING;

-- Backfill totals from the V2 ledger before installing the live projection.
WITH totals AS (
  SELECT a.owner_economic_id, ea.code,
         SUM(CASE WHEN e.delta > 0 THEN e.delta ELSE 0 END)::BIGINT AS received,
         SUM(CASE WHEN e.delta < 0 THEN -e.delta ELSE 0 END)::BIGINT AS spent
  FROM economic_entries e
  JOIN economic_accounts a ON a.id = e.account_id
  JOIN economic_assets ea ON ea.id = a.asset_id
  GROUP BY a.owner_economic_id, ea.code
)
UPDATE economic_owner_totals t
SET credit_received = COALESCE((SELECT received FROM totals WHERE owner_economic_id = t.owner_economic_id AND code = 'CREDIT'), 0),
    credit_spent = COALESCE((SELECT spent FROM totals WHERE owner_economic_id = t.owner_economic_id AND code = 'CREDIT'), 0),
    material_received = COALESCE((SELECT received FROM totals WHERE owner_economic_id = t.owner_economic_id AND code = 'MATERIAL'), 0),
    material_spent = COALESCE((SELECT spent FROM totals WHERE owner_economic_id = t.owner_economic_id AND code = 'MATERIAL'), 0),
    components_received = COALESCE((SELECT received FROM totals WHERE owner_economic_id = t.owner_economic_id AND code = 'COMPONENTS'), 0),
    components_spent = COALESCE((SELECT spent FROM totals WHERE owner_economic_id = t.owner_economic_id AND code = 'COMPONENTS'), 0),
    energy_received = COALESCE((SELECT received FROM totals WHERE owner_economic_id = t.owner_economic_id AND code = 'ENERGY'), 0),
    energy_spent = COALESCE((SELECT spent FROM totals WHERE owner_economic_id = t.owner_economic_id AND code = 'ENERGY'), 0),
    compute_received = COALESCE((SELECT received FROM totals WHERE owner_economic_id = t.owner_economic_id AND code = 'COMPUTE'), 0),
    compute_spent = COALESCE((SELECT spent FROM totals WHERE owner_economic_id = t.owner_economic_id AND code = 'COMPUTE'), 0),
    food_received = COALESCE((SELECT received FROM totals WHERE owner_economic_id = t.owner_economic_id AND code = 'FOOD'), 0),
    food_spent = COALESCE((SELECT spent FROM totals WHERE owner_economic_id = t.owner_economic_id AND code = 'FOOD'), 0),
    updated_at = CURRENT_TIMESTAMP;

CREATE OR REPLACE FUNCTION earth_update_economic_owner_totals()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO economic_owner_totals (
    owner_economic_id,
    credit_received, credit_spent, material_received, material_spent,
    components_received, components_spent, energy_received, energy_spent,
    compute_received, compute_spent, food_received, food_spent, updated_at
  )
  SELECT a.owner_economic_id,
    COALESCE(SUM(e.delta) FILTER (WHERE ea.code = 'CREDIT' AND e.delta > 0), 0),
    COALESCE(SUM(-e.delta) FILTER (WHERE ea.code = 'CREDIT' AND e.delta < 0), 0),
    COALESCE(SUM(e.delta) FILTER (WHERE ea.code = 'MATERIAL' AND e.delta > 0), 0),
    COALESCE(SUM(-e.delta) FILTER (WHERE ea.code = 'MATERIAL' AND e.delta < 0), 0),
    COALESCE(SUM(e.delta) FILTER (WHERE ea.code = 'COMPONENTS' AND e.delta > 0), 0),
    COALESCE(SUM(-e.delta) FILTER (WHERE ea.code = 'COMPONENTS' AND e.delta < 0), 0),
    COALESCE(SUM(e.delta) FILTER (WHERE ea.code = 'ENERGY' AND e.delta > 0), 0),
    COALESCE(SUM(-e.delta) FILTER (WHERE ea.code = 'ENERGY' AND e.delta < 0), 0),
    COALESCE(SUM(e.delta) FILTER (WHERE ea.code = 'COMPUTE' AND e.delta > 0), 0),
    COALESCE(SUM(-e.delta) FILTER (WHERE ea.code = 'COMPUTE' AND e.delta < 0), 0),
    COALESCE(SUM(e.delta) FILTER (WHERE ea.code = 'FOOD' AND e.delta > 0), 0),
    COALESCE(SUM(-e.delta) FILTER (WHERE ea.code = 'FOOD' AND e.delta < 0), 0),
    CURRENT_TIMESTAMP
  FROM economic_entries e
  JOIN economic_accounts a ON a.id = e.account_id
  JOIN economic_assets ea ON ea.id = a.asset_id
  JOIN new_entries n ON n.id = e.id
  GROUP BY a.owner_economic_id
  ON CONFLICT (owner_economic_id) DO UPDATE SET
    credit_received = economic_owner_totals.credit_received + EXCLUDED.credit_received,
    credit_spent = economic_owner_totals.credit_spent + EXCLUDED.credit_spent,
    material_received = economic_owner_totals.material_received + EXCLUDED.material_received,
    material_spent = economic_owner_totals.material_spent + EXCLUDED.material_spent,
    components_received = economic_owner_totals.components_received + EXCLUDED.components_received,
    components_spent = economic_owner_totals.components_spent + EXCLUDED.components_spent,
    energy_received = economic_owner_totals.energy_received + EXCLUDED.energy_received,
    energy_spent = economic_owner_totals.energy_spent + EXCLUDED.energy_spent,
    compute_received = economic_owner_totals.compute_received + EXCLUDED.compute_received,
    compute_spent = economic_owner_totals.compute_spent + EXCLUDED.compute_spent,
    food_received = economic_owner_totals.food_received + EXCLUDED.food_received,
    food_spent = economic_owner_totals.food_spent + EXCLUDED.food_spent,
    updated_at = CURRENT_TIMESTAMP;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS economic_entries_owner_totals ON economic_entries;
CREATE TRIGGER economic_entries_owner_totals
AFTER INSERT ON economic_entries
REFERENCING NEW TABLE AS new_entries
FOR EACH STATEMENT
EXECUTE FUNCTION earth_update_economic_owner_totals();
