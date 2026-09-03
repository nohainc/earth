-- Migration 100: make owner_id the canonical owner-registry reference.
-- The previous migration populated owner_registry_id as a transition aid. This
-- migration removes that compatibility layer and makes the existing owner_id
-- columns direct foreign keys to the unified owner registry.

DO $$
DECLARE table_name TEXT;
BEGIN
  FOREACH table_name IN ARRAY ARRAY['account_balances','buildings','businesses','resource_balances','resource_ledger_entries','resource_rate_history','daily_settlement_profiles','daily_settlement_profile_runs','technologies'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I', table_name || '_owner_registry_sync', table_name);
    EXECUTE format('ALTER TABLE %I DROP COLUMN IF EXISTS owner_registry_id', table_name);
  END LOOP;
END $$;

DROP FUNCTION IF EXISTS earth_sync_owner_registry();

-- Remove earlier human-only constraints where present before replacing them
-- with the owner registry constraint.
DO $$
DECLARE row_data RECORD;
BEGIN
  FOR row_data IN
    SELECT con.conname, con.conrelid::regclass AS table_name
    FROM pg_constraint con
    JOIN pg_attribute att ON att.attrelid = con.conrelid AND att.attnum = ANY(con.conkey)
    WHERE con.contype = 'f' AND att.attname = 'owner_id'
      AND con.conrelid::regclass::text IN ('account_balances','buildings','businesses','resource_balances','resource_ledger_entries','resource_rate_history','daily_settlement_profiles','daily_settlement_profile_runs','technologies')
  LOOP
    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', row_data.table_name, row_data.conname);
  END LOOP;
END $$;

ALTER TABLE account_balances ADD CONSTRAINT account_balances_owner_fk FOREIGN KEY (owner_id) REFERENCES owner_registry(id);
ALTER TABLE buildings ADD CONSTRAINT buildings_owner_fk FOREIGN KEY (owner_id) REFERENCES owner_registry(id);
ALTER TABLE businesses ADD CONSTRAINT businesses_owner_fk FOREIGN KEY (owner_id) REFERENCES owner_registry(id);
ALTER TABLE resource_balances ADD CONSTRAINT resource_balances_owner_fk FOREIGN KEY (owner_id) REFERENCES owner_registry(id);
ALTER TABLE resource_ledger_entries ADD CONSTRAINT resource_ledger_owner_fk FOREIGN KEY (owner_id) REFERENCES owner_registry(id);
ALTER TABLE resource_rate_history ADD CONSTRAINT resource_rate_history_owner_fk FOREIGN KEY (owner_id) REFERENCES owner_registry(id);
ALTER TABLE daily_settlement_profiles ADD CONSTRAINT daily_profiles_owner_fk FOREIGN KEY (owner_id) REFERENCES owner_registry(id);
ALTER TABLE daily_settlement_profile_runs ADD CONSTRAINT daily_profile_runs_owner_fk FOREIGN KEY (owner_id) REFERENCES owner_registry(id);
ALTER TABLE technologies ADD CONSTRAINT technologies_owner_fk FOREIGN KEY (owner_id) REFERENCES owner_registry(id);

ALTER TABLE owner_registry ADD CONSTRAINT owner_registry_id_source_consistency CHECK (id = source_id);

CREATE OR REPLACE FUNCTION earth_integrity_report()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT) LANGUAGE SQL AS $$
  SELECT 'buildings_missing_catalog', COUNT(*) FROM buildings b LEFT JOIN building_catalog c ON c.id=b.catalog_id WHERE b.catalog_id IS NOT NULL AND c.id IS NULL
  UNION ALL SELECT 'building_city_missing', COUNT(*) FROM buildings b LEFT JOIN cities c ON c.id=b.city_id WHERE b.city_id IS NOT NULL AND c.id IS NULL
  UNION ALL SELECT 'membership_human_missing', COUNT(*) FROM memberships m LEFT JOIN humans h ON h.id=m.human_id WHERE h.id IS NULL
  UNION ALL SELECT 'membership_city_missing', COUNT(*) FROM memberships m LEFT JOIN cities c ON c.id=m.city_id WHERE m.city_id IS NOT NULL AND c.id IS NULL
  UNION ALL SELECT 'membership_corporation_missing', COUNT(*) FROM memberships m LEFT JOIN corporations c ON c.id=m.corporation_id WHERE m.corporation_id IS NOT NULL AND c.id IS NULL
  UNION ALL SELECT 'account_owner_missing_registry', COUNT(*) FROM account_balances a LEFT JOIN owner_registry o ON o.id=a.owner_id WHERE o.id IS NULL
  UNION ALL SELECT 'building_owner_missing_registry', COUNT(*) FROM buildings b LEFT JOIN owner_registry o ON o.id=b.owner_id WHERE o.id IS NULL
  UNION ALL SELECT 'business_owner_missing_registry', COUNT(*) FROM businesses b LEFT JOIN owner_registry o ON o.id=b.owner_id WHERE o.id IS NULL;
$$;
