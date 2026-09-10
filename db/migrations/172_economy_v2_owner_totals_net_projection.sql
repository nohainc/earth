-- Economy V2 Plan 23: classify owner totals from transaction-level external nets.
-- An owner's wallet -> reserve transfer must not count as both spent and received.

-- Rebuild the projection from complete economic transactions. For each
-- transaction/owner/asset tuple, only the net delta is external activity from
-- that owner's perspective; an internal transfer therefore nets to zero.
WITH owner_asset_nets AS (
  SELECT e.transaction_id,
         a.owner_economic_id,
         a.asset_id,
         SUM(e.delta)::BIGINT AS net_delta
  FROM economic_entries e
  JOIN economic_accounts a ON a.id = e.account_id
  GROUP BY e.transaction_id, a.owner_economic_id, a.asset_id
), totals AS (
  SELECT n.owner_economic_id, x.code,
         SUM(n.net_delta) FILTER (WHERE n.net_delta > 0)::BIGINT AS received,
         SUM(-n.net_delta) FILTER (WHERE n.net_delta < 0)::BIGINT AS spent
  FROM owner_asset_nets n
  JOIN economic_assets x ON x.id = n.asset_id
  GROUP BY n.owner_economic_id, x.code
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
  -- Re-read all entries for affected transactions, because the transition
  -- table can contain only one statement's entries while a transaction may
  -- contain several entries for the same owner and asset.
  WITH affected_transactions AS (
    SELECT DISTINCT transaction_id FROM new_entries
  ), owner_asset_nets AS (
    SELECT e.transaction_id,
           a.owner_economic_id,
           a.asset_id,
           SUM(e.delta)::BIGINT AS net_delta
    FROM economic_entries e
    JOIN affected_transactions affected ON affected.transaction_id = e.transaction_id
    JOIN economic_accounts a ON a.id = e.account_id
    GROUP BY e.transaction_id, a.owner_economic_id, a.asset_id
  ), owner_totals AS (
    SELECT n.owner_economic_id,
      COALESCE(SUM(n.net_delta) FILTER (WHERE x.code = 'CREDIT' AND n.net_delta > 0), 0)::BIGINT AS credit_received,
      COALESCE(SUM(-n.net_delta) FILTER (WHERE x.code = 'CREDIT' AND n.net_delta < 0), 0)::BIGINT AS credit_spent,
      COALESCE(SUM(n.net_delta) FILTER (WHERE x.code = 'MATERIAL' AND n.net_delta > 0), 0)::BIGINT AS material_received,
      COALESCE(SUM(-n.net_delta) FILTER (WHERE x.code = 'MATERIAL' AND n.net_delta < 0), 0)::BIGINT AS material_spent,
      COALESCE(SUM(n.net_delta) FILTER (WHERE x.code = 'COMPONENTS' AND n.net_delta > 0), 0)::BIGINT AS components_received,
      COALESCE(SUM(-n.net_delta) FILTER (WHERE x.code = 'COMPONENTS' AND n.net_delta < 0), 0)::BIGINT AS components_spent,
      COALESCE(SUM(n.net_delta) FILTER (WHERE x.code = 'ENERGY' AND n.net_delta > 0), 0)::BIGINT AS energy_received,
      COALESCE(SUM(-n.net_delta) FILTER (WHERE x.code = 'ENERGY' AND n.net_delta < 0), 0)::BIGINT AS energy_spent,
      COALESCE(SUM(n.net_delta) FILTER (WHERE x.code = 'COMPUTE' AND n.net_delta > 0), 0)::BIGINT AS compute_received,
      COALESCE(SUM(-n.net_delta) FILTER (WHERE x.code = 'COMPUTE' AND n.net_delta < 0), 0)::BIGINT AS compute_spent,
      COALESCE(SUM(n.net_delta) FILTER (WHERE x.code = 'FOOD' AND n.net_delta > 0), 0)::BIGINT AS food_received,
      COALESCE(SUM(-n.net_delta) FILTER (WHERE x.code = 'FOOD' AND n.net_delta < 0), 0)::BIGINT AS food_spent
    FROM owner_asset_nets n
    JOIN economic_assets x ON x.id = n.asset_id
    GROUP BY n.owner_economic_id
  )
  INSERT INTO economic_owner_totals (
    owner_economic_id,
    credit_received, credit_spent, material_received, material_spent,
    components_received, components_spent, energy_received, energy_spent,
    compute_received, compute_spent, food_received, food_spent, updated_at
  )
  SELECT owner_economic_id,
    credit_received, credit_spent, material_received, material_spent,
    components_received, components_spent, energy_received, energy_spent,
    compute_received, compute_spent, food_received, food_spent, CURRENT_TIMESTAMP
  FROM owner_totals
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
