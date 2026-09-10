-- Proposals describe a governance decision. Their target must be a durable
-- game entity whenever one exists; the Nano Markup payload remains only for
-- proposal-specific parameters and presentation notes.

ALTER TABLE proposals
  ADD COLUMN IF NOT EXISTS target_kind TEXT NOT NULL DEFAULT 'generic',
  ADD COLUMN IF NOT EXISTS building_catalog_id TEXT,
  ADD COLUMN IF NOT EXISTS research_project_id TEXT;

ALTER TABLE proposals
  ADD CONSTRAINT proposals_target_kind_check
  CHECK (target_kind IN ('generic', 'building_catalog', 'research_project', 'finance_rule'));

ALTER TABLE proposals
  ADD CONSTRAINT proposals_building_catalog_fk
  FOREIGN KEY (building_catalog_id) REFERENCES building_catalog(id) ON DELETE RESTRICT;

ALTER TABLE proposals
  ADD CONSTRAINT proposals_research_project_fk
  FOREIGN KEY (research_project_id) REFERENCES corporation_building_research_projects(id) ON DELETE RESTRICT;

ALTER TABLE proposals
  ADD CONSTRAINT proposals_single_entity_target_check
  CHECK (num_nonnulls(building_catalog_id, research_project_id) <= 1);

CREATE INDEX IF NOT EXISTS proposals_building_catalog_target_idx
  ON proposals(building_catalog_id) WHERE building_catalog_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS proposals_research_project_target_idx
  ON proposals(research_project_id) WHERE research_project_id IS NOT NULL;
