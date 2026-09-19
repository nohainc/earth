-- EARTH ACTIVE MIGRATION: reconcile baseline functions and triggers on active databases

CREATE OR REPLACE FUNCTION earth_validate_economic_account_capability()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_owner_type TEXT;
  v_asset_kind TEXT;
BEGIN
  SELECT owner_type INTO v_owner_type
    FROM owner_registry
   WHERE economic_id = NEW.owner_economic_id;
  IF v_owner_type IS NULL THEN
    RAISE EXCEPTION 'economic account owner does not exist: %', NEW.owner_economic_id;
  END IF;

  SELECT asset_kind INTO v_asset_kind
    FROM economic_assets
   WHERE id = NEW.asset_id;
  IF v_asset_kind IS NULL THEN
    RAISE EXCEPTION 'economic account asset does not exist: %', NEW.asset_id;
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM economic_account_policies p
     WHERE p.owner_type = v_owner_type
       AND p.account_type = NEW.account_type
       AND (p.allowed_asset_kind = v_asset_kind OR p.allowed_asset_kind = 'ANY')
  ) THEN
    RAISE EXCEPTION 'economic account capability denied: owner_type=%, account_type=%, asset_kind=%',
      v_owner_type, NEW.account_type, v_asset_kind;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS economic_accounts_capability_integrity ON economic_accounts;
CREATE TRIGGER economic_accounts_capability_integrity
BEFORE INSERT OR UPDATE OF owner_economic_id, asset_id, account_type ON economic_accounts
FOR EACH ROW EXECUTE FUNCTION earth_validate_economic_account_capability();

CREATE OR REPLACE FUNCTION earth_provision_house_economy(p_economic_id TEXT)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
  v_owner_type TEXT;
  v_account_count INTEGER;
BEGIN
  SELECT owner_type INTO v_owner_type FROM owner_registry WHERE economic_id = p_economic_id;
  IF v_owner_type IS DISTINCT FROM 'HOUSE' THEN
    RAISE EXCEPTION 'House economy provisioning requires a HOUSE owner: %', p_economic_id;
  END IF;

  INSERT INTO economic_accounts(owner_economic_id, asset_id, account_type)
  SELECT p_economic_id, id, 'WALLET' FROM economic_assets WHERE asset_kind = 'CREDIT'
  ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING;
  INSERT INTO economic_accounts(owner_economic_id, asset_id, account_type)
  SELECT p_economic_id, id, 'INVENTORY' FROM economic_assets WHERE asset_kind = 'RESOURCE'
  ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING;

  SELECT COUNT(*) INTO v_account_count
    FROM economic_accounts
   WHERE owner_economic_id = p_economic_id
     AND ((account_type = 'WALLET' AND asset_id IN (SELECT id FROM economic_assets WHERE asset_kind = 'CREDIT'))
       OR (account_type = 'INVENTORY' AND asset_id IN (SELECT id FROM economic_assets WHERE asset_kind = 'RESOURCE')));
  RETURN v_account_count;
END;
$$;

CREATE OR REPLACE FUNCTION earth_provision_earth_economy(p_economic_id TEXT)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
  v_owner_type TEXT;
  v_account_count INTEGER;
BEGIN
  SELECT owner_type INTO v_owner_type FROM owner_registry WHERE economic_id = p_economic_id;
  IF v_owner_type IS DISTINCT FROM 'EARTH' THEN
    RAISE EXCEPTION 'EARTH economy provisioning requires an EARTH owner: %', p_economic_id;
  END IF;

  INSERT INTO economic_accounts(owner_economic_id, asset_id, account_type)
  SELECT p_economic_id, id, account_type
    FROM economic_assets
   CROSS JOIN (VALUES ('TREASURY'::TEXT), ('OPERATIONS'::TEXT), ('RESERVE'::TEXT)) types(account_type)
   WHERE asset_kind = 'CREDIT'
  ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING;

  SELECT COUNT(*) INTO v_account_count
    FROM economic_accounts
   WHERE owner_economic_id = p_economic_id AND account_type IN ('TREASURY', 'OPERATIONS', 'RESERVE')
     AND asset_id IN (SELECT id FROM economic_assets WHERE asset_kind = 'CREDIT');
  RETURN v_account_count;
END;
$$;

CREATE OR REPLACE FUNCTION earth_provision_bank_economy(p_economic_id TEXT)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
  v_owner_type TEXT;
  v_account_count INTEGER;
BEGIN
  SELECT owner_type INTO v_owner_type FROM owner_registry WHERE economic_id = p_economic_id;
  IF v_owner_type IS DISTINCT FROM 'BANK' THEN
    RAISE EXCEPTION 'Bank economy provisioning requires a BANK owner: %', p_economic_id;
  END IF;

  INSERT INTO economic_accounts(owner_economic_id, asset_id, account_type)
  SELECT p_economic_id, id, account_type
    FROM economic_assets
   CROSS JOIN (VALUES ('OPERATIONS'::TEXT), ('RESERVE'::TEXT)) types(account_type)
   WHERE asset_kind = 'CREDIT'
  ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING;

  SELECT COUNT(*) INTO v_account_count
    FROM economic_accounts
   WHERE owner_economic_id = p_economic_id AND account_type IN ('OPERATIONS', 'RESERVE')
     AND asset_id IN (SELECT id FROM economic_assets WHERE asset_kind = 'CREDIT');
  RETURN v_account_count;
END;
$$;

CREATE OR REPLACE FUNCTION earth_daily_asset_flow(p_game_day BIGINT)
RETURNS TABLE(asset_code TEXT, asset_kind TEXT, credit_created BIGINT, credit_destroyed BIGINT, resource_produced BIGINT, resource_consumed BIGINT)
LANGUAGE SQL STABLE AS $$
  SELECT a.code, a.asset_kind,
    COALESCE(SUM(CASE WHEN k.semantic_class = 'CREDIT_ISSUANCE' AND e.delta_units > 0 THEN e.delta_units ELSE 0 END), 0)::BIGINT,
    COALESCE(SUM(CASE WHEN k.semantic_class = 'CREDIT_RETIREMENT' AND e.delta_units < 0 THEN ABS(e.delta_units) ELSE 0 END), 0)::BIGINT,
    COALESCE(SUM(CASE WHEN k.semantic_class = 'RESOURCE_PRODUCTION' AND e.delta_units > 0 AND o.owner_type <> 'SYSTEM' THEN e.delta_units ELSE 0 END), 0)::BIGINT,
    COALESCE(SUM(CASE WHEN k.semantic_class = 'RESOURCE_CONSUMPTION' AND e.delta_units < 0 AND o.owner_type <> 'SYSTEM' THEN ABS(e.delta_units) ELSE 0 END), 0)::BIGINT
    FROM economic_assets a
    LEFT JOIN economic_entries e ON e.asset_id = a.id
    LEFT JOIN economic_transactions t ON t.id = e.transaction_id AND t.game_day = p_game_day
    LEFT JOIN economic_transaction_kinds k ON k.code = t.transaction_kind
    LEFT JOIN economic_accounts ea ON ea.id = e.account_id
    LEFT JOIN owner_registry o ON o.economic_id = ea.owner_economic_id
   GROUP BY a.id, a.code, a.asset_kind
   ORDER BY a.id;
$$;

CREATE OR REPLACE FUNCTION earth_validate_building_ownership()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  owner_kind TEXT;
  ownership_scope TEXT;
  territory_corporation_id TEXT;
BEGIN
  SELECT owner_type INTO owner_kind FROM owner_registry WHERE economic_id = NEW.owner_economic_id;
  SELECT bc.ownership_scope INTO ownership_scope FROM building_catalog bc WHERE bc.id = NEW.catalog_id;
  SELECT t.corporation_id INTO territory_corporation_id FROM territories t WHERE t.id = NEW.territory_id;

  IF owner_kind IS NULL OR ownership_scope IS NULL OR territory_corporation_id IS NULL THEN
    RAISE EXCEPTION 'Building owner, blueprint, and Territory must exist';
  END IF;
  IF ownership_scope = 'PUBLIC' AND owner_kind <> 'CORPORATION' THEN
    RAISE EXCEPTION 'Public infrastructure must be Corporation-owned';
  END IF;
  IF ownership_scope = 'PRIVATE' AND owner_kind <> 'HOUSE' THEN
    RAISE EXCEPTION 'Private buildings must be House-owned';
  END IF;
  IF ownership_scope = 'PUBLIC' AND NOT EXISTS (
    SELECT 1 FROM owner_registry o
    WHERE o.id = territory_corporation_id AND o.economic_id = NEW.owner_economic_id AND o.owner_type = 'CORPORATION'
  ) THEN
    RAISE EXCEPTION 'Public infrastructure owner must be the Territory Corporation';
  END IF;
  IF ownership_scope = 'PRIVATE' AND NOT EXISTS (
    SELECT 1 FROM owner_registry o
    JOIN house_affiliations ha ON ha.house_id = o.id
    WHERE o.economic_id = NEW.owner_economic_id AND o.owner_type = 'HOUSE'
      AND ha.corporation_id = territory_corporation_id AND ha.status = 'ACTIVE'
  ) THEN
    RAISE EXCEPTION 'Private building owner must be an active House in the Territory Corporation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS buildings_ownership_integrity ON buildings;
CREATE TRIGGER buildings_ownership_integrity
BEFORE INSERT OR UPDATE OF owner_economic_id, territory_id, catalog_id ON buildings
FOR EACH ROW EXECUTE FUNCTION earth_validate_building_ownership();
