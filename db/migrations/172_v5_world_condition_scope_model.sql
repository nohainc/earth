-- V5 WORLD CONDITIONS: Earth-wide or Corporation-scoped only.
-- Territory and Organization are physical/legacy concepts, not World Condition authorities.
UPDATE world_conditions SET scope_type = 'EARTH', scope_id = NULL WHERE scope_type = 'WORLD';
DELETE FROM world_conditions WHERE scope_type IN ('TERRITORY', 'ORGANIZATION');

ALTER TABLE world_conditions DROP CONSTRAINT IF EXISTS world_conditions_scope_type_check;
ALTER TABLE world_conditions ADD CONSTRAINT world_conditions_scope_type_check
  CHECK (scope_type IN ('EARTH', 'CORPORATION'));
ALTER TABLE world_conditions DROP CONSTRAINT IF EXISTS world_conditions_scope_id_check;
ALTER TABLE world_conditions ADD CONSTRAINT world_conditions_scope_id_check
  CHECK ((scope_type = 'EARTH' AND scope_id IS NULL) OR (scope_type = 'CORPORATION' AND scope_id IS NOT NULL));

COMMENT ON COLUMN world_conditions.scope_type IS
  'V5 authority scope: EARTH for global conditions or CORPORATION for an affiliated corporation. Territory and Organization are not condition authorities.';
