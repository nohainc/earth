-- EARTH ACTIVE MIGRATION: V5 unified governance integration for public construction, scale research, and frontier advancement.

ALTER TABLE v5_governance_proposals DROP CONSTRAINT IF EXISTS v5_governance_proposals_action_type_check;
ALTER TABLE v5_governance_proposals ADD CONSTRAINT v5_governance_proposals_action_type_check
  CHECK (action_type IN (
    'CONSTITUTION_AMENDMENT',
    'CORPORATION_PUBLIC_CONSTRUCTION',
    'CORPORATION_SCALE_RESEARCH',
    'EARTH_TECHNOLOGY_FRONTIER',
    'EARTH_CAPACITY_POLICY',
    'CORPORATION_HOUSE_RATE',
    'PROGRESSIVE_SCHEDULE',
    'CORPORATION_ADMISSION_POLICY'
  ));

ALTER TABLE v5_structural_deltas DROP CONSTRAINT IF EXISTS v5_structural_deltas_building_id_fkey;
ALTER TABLE v5_structural_deltas ADD CONSTRAINT v5_structural_deltas_building_id_fkey
  FOREIGN KEY (building_id) REFERENCES buildings(id) ON DELETE CASCADE;

ALTER TABLE v5_structural_deltas DROP CONSTRAINT IF EXISTS v5_structural_deltas_house_id_fkey;
ALTER TABLE v5_structural_deltas ADD CONSTRAINT v5_structural_deltas_house_id_fkey
  FOREIGN KEY (house_id) REFERENCES houses(id) ON DELETE CASCADE;

ALTER TABLE v5_structural_deltas DROP CONSTRAINT IF EXISTS v5_structural_deltas_corporation_id_fkey;
ALTER TABLE v5_structural_deltas ADD CONSTRAINT v5_structural_deltas_corporation_id_fkey
  FOREIGN KEY (corporation_id) REFERENCES corporations(id) ON DELETE CASCADE;

