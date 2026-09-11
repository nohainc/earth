-- Technology & Research V2 Plan 30: dissolved corporate IP moves to the OUC
-- IP registry without deleting rights or license obligations.

CREATE TABLE IF NOT EXISTS technology_patent_ownership_transfers (
  id BIGSERIAL PRIMARY KEY,
  patent_id TEXT NOT NULL REFERENCES technology_patents(id),
  from_owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  to_owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS technology_patent_ownership_transfer_once_idx
  ON technology_patent_ownership_transfers (patent_id, from_owner_economic_id, to_owner_economic_id);

CREATE OR REPLACE FUNCTION earth_transfer_dissolved_corporation_ip(
  p_corporation_id TEXT,
  p_game_day BIGINT,
  p_correlation_id TEXT
)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
  v_from_owner BIGINT;
  v_ouc_owner BIGINT;
  v_count BIGINT := 0;
  v_patent RECORD;
BEGIN
  SELECT economic_id INTO v_from_owner
  FROM owner_registry WHERE id = p_corporation_id AND owner_type ILIKE 'corporation';
  SELECT economic_id INTO v_ouc_owner
  FROM owner_registry WHERE id = 'OUC' AND status = 'active';
  IF v_from_owner IS NULL OR v_ouc_owner IS NULL THEN
    RAISE EXCEPTION 'Corporation or OUC IP registry owner is unavailable';
  END IF;
  IF v_from_owner = v_ouc_owner THEN RAISE EXCEPTION 'Cannot transfer OUC IP to itself'; END IF;

  IF EXISTS (SELECT 1 FROM technology_patent_ownership_transfers WHERE correlation_id = p_correlation_id) THEN
    RETURN 0;
  END IF;

  FOR v_patent IN
    SELECT id FROM technology_patents
    WHERE owner_economic_id = v_from_owner AND status IN ('ACTIVE', 'EXPIRED')
    ORDER BY id FOR UPDATE
  LOOP
    UPDATE technology_patents SET owner_economic_id = v_ouc_owner WHERE id = v_patent.id;
    UPDATE technology_license_contracts
    SET licensor_economic_id = v_ouc_owner
    WHERE patent_id = v_patent.id
      AND status IN ('PENDING', 'ACTIVE', 'SUSPENDED');
    INSERT INTO technology_patent_ownership_transfers
      (patent_id, from_owner_economic_id, to_owner_economic_id, game_day, correlation_id)
    VALUES (v_patent.id, v_from_owner, v_ouc_owner, p_game_day,
            p_correlation_id || ':' || v_patent.id)
    ON CONFLICT DO NOTHING;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION earth_transfer_dissolved_corporation_ip(TEXT, BIGINT, TEXT) IS
  'Transfers dissolved corporation patents and future license income to the OUC IP registry.';
