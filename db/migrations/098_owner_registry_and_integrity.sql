-- Migration 098: replace implicit polymorphic ownership with an auditable registry.

CREATE TABLE IF NOT EXISTS owner_registry (
  id TEXT PRIMARY KEY,
  owner_type TEXT NOT NULL CHECK (owner_type IN ('human','city','corporation','community','system','legacy')),
  source_id TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','closed','archived')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO owner_registry (id, owner_type, source_id)
SELECT id, 'human', id FROM humans ON CONFLICT (source_id) DO NOTHING;
INSERT INTO owner_registry (id, owner_type, source_id)
SELECT id, 'city', id FROM cities ON CONFLICT (source_id) DO NOTHING;
INSERT INTO owner_registry (id, owner_type, source_id)
SELECT id, 'corporation', id FROM corporations ON CONFLICT (source_id) DO NOTHING;
INSERT INTO owner_registry (id, owner_type, source_id)
SELECT id, 'community', id FROM communities ON CONFLICT (source_id) DO NOTHING;
INSERT INTO owner_registry (id, owner_type, source_id)
VALUES ('SYSTEM','system','SYSTEM'), ('OUC','system','OUC') ON CONFLICT (source_id) DO NOTHING;

-- Preserve existing institutional/system references while making them explicit.
INSERT INTO owner_registry (id, owner_type, source_id)
SELECT DISTINCT source_id,
  CASE
    WHEN source_id LIKE 'CITY-%' THEN 'city'
    WHEN source_id LIKE 'CORP-%' THEN 'corporation'
    WHEN source_id LIKE 'COMM-%' THEN 'community'
    WHEN source_id LIKE 'TEST-CITY-%' THEN 'city'
    ELSE 'legacy'
  END,
  source_id
FROM (
  SELECT owner_id AS source_id FROM account_balances WHERE owner_id IS NOT NULL
  UNION SELECT owner_id FROM resource_balances WHERE owner_id IS NOT NULL
  UNION SELECT owner_id FROM resource_ledger_entries WHERE owner_id IS NOT NULL
  UNION SELECT owner_id FROM resource_rate_history WHERE owner_id IS NOT NULL
  UNION SELECT owner_id FROM daily_settlement_profiles WHERE owner_id IS NOT NULL
  UNION SELECT owner_id FROM daily_settlement_profile_runs WHERE owner_id IS NOT NULL
  UNION SELECT owner_id FROM buildings WHERE owner_id IS NOT NULL
  UNION SELECT owner_id FROM businesses WHERE owner_id IS NOT NULL
  UNION SELECT owner_id FROM technologies WHERE owner_id IS NOT NULL
) refs
ON CONFLICT (source_id) DO NOTHING;

-- Repair historical catalog aliases before enforcing the building catalog FK.
UPDATE buildings SET catalog_id = 'vertical-farm-t1'
WHERE building_type = 'hydroponic_farm' AND catalog_id = 'hydroponic_farm-t1';
UPDATE buildings SET catalog_id = 'solar-array-complex-t1'
WHERE building_type = 'solar_power_plant' AND catalog_id = 'solar_power_plant-t1';

ALTER TABLE humans ADD COLUMN IF NOT EXISTS account_status TEXT NOT NULL DEFAULT 'active';
ALTER TABLE humans ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE humans DROP CONSTRAINT IF EXISTS humans_account_status_check;
ALTER TABLE humans ADD CONSTRAINT humans_account_status_check CHECK (account_status IN ('active','closed'));

ALTER TABLE account_balances ADD COLUMN IF NOT EXISTS owner_registry_id TEXT;
ALTER TABLE buildings ADD COLUMN IF NOT EXISTS owner_registry_id TEXT;
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS owner_registry_id TEXT;
ALTER TABLE resource_balances ADD COLUMN IF NOT EXISTS owner_registry_id TEXT;
ALTER TABLE resource_ledger_entries ADD COLUMN IF NOT EXISTS owner_registry_id TEXT;
ALTER TABLE resource_rate_history ADD COLUMN IF NOT EXISTS owner_registry_id TEXT;
ALTER TABLE daily_settlement_profiles ADD COLUMN IF NOT EXISTS owner_registry_id TEXT;
ALTER TABLE daily_settlement_profile_runs ADD COLUMN IF NOT EXISTS owner_registry_id TEXT;
ALTER TABLE technologies ADD COLUMN IF NOT EXISTS owner_registry_id TEXT;

UPDATE account_balances t SET owner_registry_id = r.id FROM owner_registry r WHERE r.source_id=t.owner_id AND t.owner_registry_id IS NULL;
UPDATE buildings t SET owner_registry_id = r.id FROM owner_registry r WHERE r.source_id=t.owner_id AND t.owner_registry_id IS NULL;
UPDATE businesses t SET owner_registry_id = r.id FROM owner_registry r WHERE r.source_id=t.owner_id AND t.owner_registry_id IS NULL;
UPDATE resource_balances t SET owner_registry_id = r.id FROM owner_registry r WHERE r.source_id=t.owner_id AND t.owner_registry_id IS NULL;
UPDATE resource_ledger_entries t SET owner_registry_id = r.id FROM owner_registry r WHERE r.source_id=t.owner_id AND t.owner_registry_id IS NULL;
UPDATE resource_rate_history t SET owner_registry_id = r.id FROM owner_registry r WHERE r.source_id=t.owner_id AND t.owner_registry_id IS NULL;
UPDATE daily_settlement_profiles t SET owner_registry_id = r.id FROM owner_registry r WHERE r.source_id=t.owner_id AND t.owner_registry_id IS NULL;
UPDATE daily_settlement_profile_runs t SET owner_registry_id = r.id FROM owner_registry r WHERE r.source_id=t.owner_id AND t.owner_registry_id IS NULL;
UPDATE technologies t SET owner_registry_id = r.id FROM owner_registry r WHERE r.source_id=t.owner_id AND t.owner_registry_id IS NULL;

CREATE OR REPLACE FUNCTION earth_sync_owner_registry()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.owner_id IS NULL THEN
    NEW.owner_registry_id := NULL;
  ELSE
    SELECT id INTO NEW.owner_registry_id FROM owner_registry WHERE source_id = NEW.owner_id;
    IF NEW.owner_registry_id IS NULL THEN
      RAISE EXCEPTION 'Unknown owner_id %; register the owner before writing this record', NEW.owner_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DO $$
DECLARE table_name TEXT;
BEGIN
  FOREACH table_name IN ARRAY ARRAY['account_balances','buildings','businesses','resource_balances','resource_ledger_entries','resource_rate_history','daily_settlement_profiles','daily_settlement_profile_runs','technologies'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I', table_name || '_owner_registry_sync', table_name);
    EXECUTE format('CREATE TRIGGER %I BEFORE INSERT OR UPDATE OF owner_id ON %I FOR EACH ROW EXECUTE FUNCTION earth_sync_owner_registry()', table_name || '_owner_registry_sync', table_name);
  END LOOP;
END $$;

ALTER TABLE account_balances ADD CONSTRAINT account_balances_owner_registry_fk FOREIGN KEY (owner_registry_id) REFERENCES owner_registry(id);
ALTER TABLE buildings ADD CONSTRAINT buildings_owner_registry_fk FOREIGN KEY (owner_registry_id) REFERENCES owner_registry(id);
ALTER TABLE businesses ADD CONSTRAINT businesses_owner_registry_fk FOREIGN KEY (owner_registry_id) REFERENCES owner_registry(id);
ALTER TABLE resource_balances ADD CONSTRAINT resource_balances_owner_registry_fk FOREIGN KEY (owner_registry_id) REFERENCES owner_registry(id);
ALTER TABLE resource_ledger_entries ADD CONSTRAINT resource_ledger_owner_registry_fk FOREIGN KEY (owner_registry_id) REFERENCES owner_registry(id);
ALTER TABLE resource_rate_history ADD CONSTRAINT resource_rate_history_owner_registry_fk FOREIGN KEY (owner_registry_id) REFERENCES owner_registry(id);
ALTER TABLE daily_settlement_profiles ADD CONSTRAINT daily_profiles_owner_registry_fk FOREIGN KEY (owner_registry_id) REFERENCES owner_registry(id);
ALTER TABLE daily_settlement_profile_runs ADD CONSTRAINT daily_profile_runs_owner_registry_fk FOREIGN KEY (owner_registry_id) REFERENCES owner_registry(id);
ALTER TABLE technologies ADD CONSTRAINT technologies_owner_registry_fk FOREIGN KEY (owner_registry_id) REFERENCES owner_registry(id);

-- Clean legacy catalog references before enforcing the canonical catalog FK.
-- A historical building may point to a tier that is no longer present in the
-- immutable catalog (for example geothermal-grid-t3). Preserve the building
-- record, but clear only the unresolved catalog reference; later catalog
-- migrations can assign a canonical Tier 1 blueprint where appropriate.
UPDATE buildings b
SET catalog_id = NULL
WHERE b.catalog_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM building_catalog c WHERE c.id = b.catalog_id
  );

ALTER TABLE buildings ADD CONSTRAINT buildings_catalog_fk FOREIGN KEY (catalog_id) REFERENCES building_catalog(id) ON DELETE RESTRICT;
CREATE INDEX IF NOT EXISTS owner_registry_type_status_idx ON owner_registry(owner_type, status);
CREATE INDEX IF NOT EXISTS buildings_owner_registry_idx ON buildings(owner_registry_id, status);

CREATE OR REPLACE FUNCTION earth_close_human(p_human_id TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  UPDATE humans SET account_status='closed', deleted_at=COALESCE(deleted_at, NOW()) WHERE id=p_human_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Human % not found', p_human_id; END IF;
  UPDATE owner_registry SET status='closed', updated_at=NOW() WHERE source_id=p_human_id;
  UPDATE auth_sessions SET revoked_at=NOW() WHERE human_id=p_human_id AND revoked_at IS NULL;
END;
$$;

CREATE OR REPLACE FUNCTION earth_integrity_report()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT) LANGUAGE SQL AS $$
  SELECT 'buildings_missing_catalog', COUNT(*) FROM buildings b LEFT JOIN building_catalog c ON c.id=b.catalog_id WHERE b.catalog_id IS NOT NULL AND c.id IS NULL
  UNION ALL SELECT 'owner_registry_missing', COUNT(*) FROM buildings b WHERE b.owner_registry_id IS NULL
  UNION ALL SELECT 'building_city_missing', COUNT(*) FROM buildings b LEFT JOIN cities c ON c.id=b.city_id WHERE b.city_id IS NOT NULL AND c.id IS NULL
  UNION ALL SELECT 'membership_human_missing', COUNT(*) FROM memberships m LEFT JOIN humans h ON h.id=m.human_id WHERE h.id IS NULL
  UNION ALL SELECT 'membership_city_missing', COUNT(*) FROM memberships m LEFT JOIN cities c ON c.id=m.city_id WHERE m.city_id IS NOT NULL AND c.id IS NULL
  UNION ALL SELECT 'membership_corporation_missing', COUNT(*) FROM memberships m LEFT JOIN corporations c ON c.id=m.corporation_id WHERE m.corporation_id IS NOT NULL AND c.id IS NULL;
$$;
