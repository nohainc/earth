-- Death, Inheritance & House Continuity V2 Plan 3.
-- A House is the durable private economic owner. Humans remain the mortal
-- social/governance identity, but their private balances and contracts follow
-- the House without inheritance transfers.

ALTER TABLE owner_registry
  DROP CONSTRAINT IF EXISTS owner_registry_owner_type_check;
ALTER TABLE owner_registry
  ADD CONSTRAINT owner_registry_owner_type_check
  CHECK (owner_type IN ('human','house','city','corporation','community','system','legacy'));

INSERT INTO owner_registry (id, owner_type, source_id, status)
SELECT h.id, 'house', h.id,
       CASE WHEN h.status = 'ACTIVE' THEN 'active' ELSE 'closed' END
FROM houses h
ON CONFLICT (source_id) DO UPDATE
SET owner_type = 'house', status = EXCLUDED.status, updated_at = CURRENT_TIMESTAMP;

-- Every House receives one settlement account for each private asset. The
-- account identity is stable across all generations of the House.
INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type, is_default_settlement, status, legacy_account_id)
SELECT owner.economic_id,
       asset.id,
       CASE WHEN asset.id = 1 THEN 1 ELSE 2 END,
       TRUE,
       'active',
       'house:' || owner.id || ':' || asset.code
FROM owner_registry owner
JOIN economic_assets asset ON TRUE
WHERE owner.owner_type = 'house'
  AND NOT EXISTS (
    SELECT 1 FROM economic_accounts existing
    WHERE existing.owner_economic_id = owner.economic_id
      AND existing.asset_id = asset.id
      AND existing.account_type = CASE WHEN asset.id = 1 THEN 1 ELSE 2 END
  );

-- Capture the old account IDs before consolidating generations into their
-- House accounts. This temporary map also lets historical entries and the
-- compatibility mapping continue to point at the same economic value.
CREATE TEMP TABLE house_private_account_map (
  old_account_id BIGINT PRIMARY KEY,
  house_account_id BIGINT NOT NULL
) ON COMMIT DROP;

INSERT INTO house_private_account_map (old_account_id, house_account_id)
SELECT old.id, house_account.id
FROM economic_accounts old
JOIN owner_registry human_owner ON human_owner.economic_id = old.owner_economic_id
JOIN humans human ON human.id = human_owner.id
JOIN owner_registry house_owner ON house_owner.id = human.house_id AND house_owner.owner_type = 'house'
JOIN economic_accounts house_account
  ON house_account.owner_economic_id = house_owner.economic_id
 AND house_account.asset_id = old.asset_id
 AND house_account.account_type = old.account_type
 AND house_account.is_default_settlement
 AND house_account.status = 'active'
WHERE human_owner.owner_type = 'human'
  AND old.account_type IN (1, 2)
  AND old.status = 'active';

-- Move the existing authoritative V2 balances without creating an economic
-- transfer. All generations belonging to one House are consolidated.
UPDATE economic_accounts house_account
SET balance = totals.balance,
    updated_at = CURRENT_TIMESTAMP
FROM (
  SELECT map.house_account_id, SUM(old.balance)::BIGINT AS balance
  FROM house_private_account_map map
  JOIN economic_accounts old ON old.id = map.old_account_id
  GROUP BY map.house_account_id
) totals
WHERE house_account.id = totals.house_account_id;

UPDATE economic_entries entry
SET account_id = map.house_account_id
FROM house_private_account_map map
WHERE entry.account_id = map.old_account_id;

UPDATE economic_account_migrations mapping
SET economic_account_id = map.house_account_id
FROM house_private_account_map map
WHERE mapping.economic_account_id = map.old_account_id;

UPDATE economic_accounts old
SET balance = 0,
    is_default_settlement = FALSE,
    status = 'closed',
    updated_at = CURRENT_TIMESTAMP
FROM house_private_account_map map
WHERE old.id = map.old_account_id;

-- Private economic contracts and projections now identify the House. Human
-- IDs remain on domain/history records where they describe the mortal actor.
UPDATE market_orders order_row
SET owner_economic_id = house_owner.economic_id
FROM humans human
JOIN owner_registry house_owner ON house_owner.id = human.house_id
WHERE order_row.human_id = human.id;

UPDATE derivative_obligations obligation
SET long_owner_economic_id = house_owner.economic_id
FROM owner_registry human_owner
JOIN humans human ON human.id = human_owner.id
JOIN owner_registry house_owner ON house_owner.id = human.house_id
WHERE obligation.long_owner_economic_id = human_owner.economic_id;

UPDATE derivative_obligations obligation
SET short_owner_economic_id = house_owner.economic_id
FROM owner_registry human_owner
JOIN humans human ON human.id = human_owner.id
JOIN owner_registry house_owner ON house_owner.id = human.house_id
WHERE obligation.short_owner_economic_id = human_owner.economic_id;

UPDATE bank_deposits deposit
SET depositor_economic_id = house_owner.economic_id
FROM owner_registry human_owner
JOIN humans human ON human.id = human_owner.id
JOIN owner_registry house_owner ON house_owner.id = human.house_id
WHERE deposit.depositor_economic_id = human_owner.economic_id;

UPDATE bank_loans loan
SET borrower_economic_id = house_owner.economic_id,
    borrower_type = 'house'
FROM owner_registry human_owner
JOIN humans human ON human.id = human_owner.id
JOIN owner_registry house_owner ON house_owner.id = human.house_id
WHERE loan.borrower_economic_id = human_owner.economic_id;

UPDATE tax_obligations obligation
SET taxpayer_economic_id = house_owner.economic_id
FROM owner_registry human_owner
JOIN humans human ON human.id = human_owner.id
JOIN owner_registry house_owner ON house_owner.id = human.house_id
WHERE obligation.taxpayer_economic_id = human_owner.economic_id;

ALTER TABLE bank_loans
  DROP CONSTRAINT IF EXISTS bank_loans_borrower_type_check;
ALTER TABLE bank_loans
  ADD CONSTRAINT bank_loans_borrower_type_check
  CHECK (borrower_type IN ('human', 'house', 'city', 'corporation'));

CREATE OR REPLACE FUNCTION earth_private_economic_owner_id(p_human_id TEXT)
RETURNS BIGINT
LANGUAGE SQL
STABLE
STRICT
AS $$
  SELECT house_owner.economic_id
  FROM humans human
  JOIN owner_registry house_owner
    ON house_owner.id = human.house_id
   AND house_owner.owner_type = 'house'
   AND house_owner.status = 'active'
  WHERE human.id = p_human_id;
$$;

COMMENT ON FUNCTION earth_private_economic_owner_id(TEXT) IS
  'Resolves a mortal Human to the persistent House economic owner.';
