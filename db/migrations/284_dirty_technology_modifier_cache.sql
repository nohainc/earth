-- Technology & Research V2 Plan 32: dirty-aware modifier read model.

CREATE TABLE IF NOT EXISTS corporation_technology_modifier_invalidations (
  corporation_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  effective_game_day BIGINT NOT NULL CHECK (effective_game_day >= 0),
  reason_code TEXT NOT NULL,
  source_id TEXT NOT NULL,
  resolved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (corporation_economic_id, effective_game_day, reason_code, source_id)
);

CREATE INDEX IF NOT EXISTS corporation_technology_modifier_invalidations_pending_idx
  ON corporation_technology_modifier_invalidations (effective_game_day, corporation_economic_id)
  WHERE resolved_at IS NULL;

CREATE OR REPLACE FUNCTION earth_mark_corporation_technology_modifiers_dirty(
  p_corporation_economic_id BIGINT,
  p_effective_game_day BIGINT,
  p_reason_code TEXT,
  p_source_id TEXT
)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO corporation_technology_modifier_invalidations
    (corporation_economic_id, effective_game_day, reason_code, source_id)
  VALUES (p_corporation_economic_id, p_effective_game_day, p_reason_code, p_source_id)
  ON CONFLICT DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION earth_invalidate_technology_modifier_cache_on_access_change()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  PERFORM earth_mark_corporation_technology_modifiers_dirty(
    NEW.corporation_economic_id,
    NEW.effective_from_game_day,
    'TECHNOLOGY_ACCESS_CHANGED',
    NEW.source_id
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS corporation_technology_access_modifier_invalidation_trigger
  ON corporation_technology_access;
CREATE TRIGGER corporation_technology_access_modifier_invalidation_trigger
  AFTER INSERT OR UPDATE OF status, effective_from_game_day, effective_to_game_day
  ON corporation_technology_access
  FOR EACH ROW EXECUTE FUNCTION earth_invalidate_technology_modifier_cache_on_access_change();

ALTER FUNCTION earth_rebuild_corporation_technology_modifier_cache(BIGINT)
  RENAME TO earth_rebuild_corporation_technology_modifier_cache_bulk;

CREATE OR REPLACE FUNCTION earth_rebuild_corporation_technology_modifier_cache(p_game_day BIGINT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
  v_count BIGINT;
BEGIN
  IF EXISTS (
    SELECT 1 FROM corporation_technology_modifier_invalidations
    WHERE effective_game_day <= p_game_day AND resolved_at IS NULL
  ) THEN
    v_count := earth_rebuild_corporation_technology_modifier_cache_bulk(p_game_day);
    UPDATE corporation_technology_modifier_invalidations
    SET resolved_at = CURRENT_TIMESTAMP
    WHERE effective_game_day <= p_game_day AND resolved_at IS NULL;
    RETURN v_count;
  END IF;

  -- No economic state changed: carry forward the compact projection without
  -- re-resolving every technology effect.
  INSERT INTO corporation_technology_modifier_cache (
    corporation_economic_id, game_day, production_output_bps, material_input_bps,
    energy_input_bps, construction_time_bps, construction_cost_bps, wear_bps,
    repair_efficiency_bps, research_capacity_bps, service_capacity_bps,
    scoped_modifiers, source_count
  )
  SELECT DISTINCT ON (corporation_economic_id)
    corporation_economic_id, p_game_day, production_output_bps, material_input_bps,
    energy_input_bps, construction_time_bps, construction_cost_bps, wear_bps,
    repair_efficiency_bps, research_capacity_bps, service_capacity_bps,
    scoped_modifiers, source_count
  FROM corporation_technology_modifier_cache
  WHERE game_day < p_game_day
  ORDER BY corporation_economic_id, game_day DESC
  ON CONFLICT (corporation_economic_id, game_day) DO NOTHING;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON TABLE corporation_technology_modifier_invalidations IS
  'Dirty events controlling rebuilds of the compact corporation technology modifier projection.';
