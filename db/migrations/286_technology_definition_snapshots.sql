-- Technology & Research V2 Plan 34: immutable definition snapshots.

ALTER TABLE corporation_research_projects
  ADD COLUMN IF NOT EXISTS definition_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB;
ALTER TABLE technology_license_contracts
  ADD COLUMN IF NOT EXISTS definition_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB,
  ADD COLUMN IF NOT EXISTS patent_terms_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB;

CREATE OR REPLACE FUNCTION earth_snapshot_technology_license_terms()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_technology_id TEXT;
BEGIN
  IF NEW.definition_snapshot = '{}'::JSONB OR NEW.patent_terms_snapshot = '{}'::JSONB THEN
    SELECT p.technology_id INTO v_technology_id FROM technology_patents p WHERE p.id = NEW.patent_id;
    IF v_technology_id IS NOT NULL THEN
      IF NEW.definition_snapshot = '{}'::JSONB THEN
        SELECT jsonb_build_object(
          'technologyId', t.id, 'code', t.code, 'name', t.name,
          'definitionVersion', t.definition_version,
          'researchCreditCostUnits', t.research_credit_cost_units,
          'researchPointsRequired', t.research_points_required,
          'effects', COALESCE((SELECT jsonb_agg(jsonb_build_object(
            'effectType', e.effect_type, 'targetType', e.target_type,
            'targetKey', e.target_key, 'modifierBps', e.modifier_bps
          ) ORDER BY e.id) FROM technology_effects e WHERE e.technology_id = t.id), '[]'::JSONB)
        ) INTO NEW.definition_snapshot
        FROM technology_catalog t WHERE t.id = v_technology_id;
      END IF;
      IF NEW.patent_terms_snapshot = '{}'::JSONB THEN
        SELECT jsonb_build_object(
          'patentable', t.patentable,
          'patentExclusivityDays', t.patent_exclusivity_days,
          'exclusiveThroughGameDay', p.exclusive_through_game_day
        ) INTO NEW.patent_terms_snapshot
        FROM technology_catalog t JOIN technology_patents p ON p.technology_id = t.id
        WHERE p.id = NEW.patent_id;
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS technology_license_definition_snapshot_trigger ON technology_license_contracts;
CREATE TRIGGER technology_license_definition_snapshot_trigger
  BEFORE INSERT ON technology_license_contracts
  FOR EACH ROW EXECUTE FUNCTION earth_snapshot_technology_license_terms();

UPDATE technology_license_contracts c
SET definition_snapshot = jsonb_build_object(
      'technologyId', t.id, 'code', t.code, 'name', t.name,
      'definitionVersion', t.definition_version,
      'researchCreditCostUnits', t.research_credit_cost_units,
      'researchPointsRequired', t.research_points_required,
      'effects', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'effectType', e.effect_type, 'targetType', e.target_type,
        'targetKey', e.target_key, 'modifierBps', e.modifier_bps
      ) ORDER BY e.id) FROM technology_effects e WHERE e.technology_id = t.id), '[]'::JSONB)
    ),
    patent_terms_snapshot = jsonb_build_object(
      'patentable', t.patentable,
      'patentExclusivityDays', t.patent_exclusivity_days,
      'exclusiveThroughGameDay', p.exclusive_through_game_day
    )
FROM technology_patents p JOIN technology_catalog t ON t.id = p.technology_id
WHERE c.patent_id = p.id
  AND (c.definition_snapshot = '{}'::JSONB OR c.patent_terms_snapshot = '{}'::JSONB);

COMMENT ON COLUMN corporation_research_projects.definition_snapshot IS
  'Immutable technology or blueprint definition used by this research project.';
