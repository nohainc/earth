-- Typed Initiative outcomes. Every completed Initiative has an explicit effect
-- or an explicit non-economic/prestige result.

CREATE TABLE IF NOT EXISTS initiative_effect_applications (
  id TEXT PRIMARY KEY,
  initiative_id TEXT NOT NULL REFERENCES v5_initiatives(id),
  outcome_id TEXT NOT NULL UNIQUE REFERENCES initiative_outcomes(id),
  effect_type TEXT NOT NULL CHECK (effect_type IN ('SERVICE_CAPACITY','TECHNOLOGY_EFFECT','CAPACITY_EFFECT','PUBLIC_ASSET','PRESTIGE')),
  target_scope TEXT NOT NULL CHECK (target_scope IN ('EARTH','CORPORATION')),
  target_id TEXT,
  payload JSONB NOT NULL CHECK (jsonb_typeof(payload) = 'object'),
  applied_game_day BIGINT NOT NULL CHECK (applied_game_day >= 1),
  status TEXT NOT NULL DEFAULT 'APPLIED' CHECK (status IN ('APPLIED','REVOKED')),
  CHECK ((target_scope = 'EARTH' AND target_id IS NULL) OR (target_scope = 'CORPORATION' AND target_id IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS initiative_effect_applications_target_idx ON initiative_effect_applications(effect_type, target_scope, target_id, status);

-- Old migrated rows are intentionally explicit non-economic history, not fake
-- gameplay effects. New proposals cannot use this compatibility type.
UPDATE initiative_outcomes
   SET outcome_type = 'LEGACY_NON_ECONOMIC'
 WHERE outcome_type IN ('LEGACY_PROGRAM_OUTPUT','LEGACY_PUBLIC_PROJECT_OUTPUT');

ALTER TABLE initiative_outcomes DROP CONSTRAINT IF EXISTS initiative_outcomes_type_check;
ALTER TABLE initiative_outcomes ADD CONSTRAINT initiative_outcomes_type_check
  CHECK (outcome_type IN ('ECONOMIC_MODIFIER','SERVICE_CAPACITY','TECHNOLOGY_EFFECT','CAPACITY_EFFECT','PUBLIC_ASSET','PRESTIGE','LEGACY_NON_ECONOMIC'));
