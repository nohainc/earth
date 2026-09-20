-- Corporation is the institutional ranking subject. Humans and Territories
-- remain outside the V5 ranking actor model.

ALTER TABLE ranking_metric_definitions
  DROP CONSTRAINT IF EXISTS ranking_metric_definitions_category_check;
ALTER TABLE ranking_metric_definitions
  ADD CONSTRAINT ranking_metric_definitions_category_check
  CHECK (category IN ('HOUSE', 'CORPORATION', 'ORGANIZATION', 'TERRITORY'));

ALTER TABLE ranking_snapshot_entries
  DROP CONSTRAINT IF EXISTS ranking_snapshot_entries_subject_type_check;
ALTER TABLE ranking_snapshot_entries
  ADD CONSTRAINT ranking_snapshot_entries_subject_type_check
  CHECK (subject_type IN ('HOUSE', 'CORPORATION', 'ORGANIZATION', 'TERRITORY'));

ALTER TABLE latest_ranking_metric_values
  DROP CONSTRAINT IF EXISTS latest_ranking_metric_values_subject_type_check;
ALTER TABLE latest_ranking_metric_values
  ADD CONSTRAINT latest_ranking_metric_values_subject_type_check
  CHECK (subject_type IN ('HOUSE', 'CORPORATION'));

INSERT INTO ranking_metric_definitions
  (metric_code, category, title, methodology, rules_version, status,
   description, value_type, unit, calculation_source, time_window, tie_behavior,
   subject_type, formula)
VALUES
  ('CORPORATION_MEMBER_HOUSES', 'CORPORATION', 'Member Houses', 'Active Houses affiliated with the Corporation.', 'rankings-v2', 'ACTIVE', 'Active Houses affiliated with the Corporation.', 'COUNT', 'COUNT', 'house_affiliations.house_id joined to corporations where affiliation.status=ACTIVE', 'CURRENT', 'VALUE_DESC_SUBJECT_ID_ASC', 'CORPORATION', 'COUNT(DISTINCT house_affiliations.house_id) grouped by Corporation where affiliation.status=ACTIVE'),
  ('CORPORATION_LIQUID_CREDIT', 'CORPORATION', 'Corporation liquid CREDIT', 'Current CREDIT account balance owned by the Corporation.', 'rankings-v2', 'ACTIVE', 'Current CREDIT account balance owned by the Corporation.', 'CREDIT_UNITS', 'CREDIT', 'economic_accounts.balance_units joined to economic_assets.code=CREDIT for Corporation owner', 'CURRENT', 'VALUE_DESC_SUBJECT_ID_ASC', 'CORPORATION', 'SUM(economic_accounts.balance_units) grouped by Corporation where account is ACTIVE and economic_assets.code=CREDIT'),
  ('CORPORATION_CAPACITY', 'CORPORATION', 'Corporation capacity', 'Active building capacity footprints owned by the Corporation.', 'rankings-v2', 'ACTIVE', 'Active building capacity footprints owned by the Corporation.', 'CAPACITY_UNITS', 'CAPACITY', 'buildings.slot_footprint via building_catalog.slot_footprint where owner is a Corporation and building.status=ACTIVE', 'CURRENT', 'VALUE_DESC_SUBJECT_ID_ASC', 'CORPORATION', 'SUM(building_catalog.slot_footprint) grouped by Corporation where building.status=ACTIVE'),
  ('CORPORATION_TECHNOLOGY', 'CORPORATION', 'Corporation technology access', 'Active technologies adopted or made available through the Corporation technology registry.', 'rankings-v2', 'ACTIVE', 'Active technologies adopted or made available through the Corporation technology registry.', 'COUNT', 'COUNT', 'corporation_technology_access.technology_id where access.status=ACTIVE', 'CURRENT', 'VALUE_DESC_SUBJECT_ID_ASC', 'CORPORATION', 'COUNT(DISTINCT corporation_technology_access.technology_id) grouped by Corporation where access.status=ACTIVE')
ON CONFLICT (metric_code) DO UPDATE SET
  category = EXCLUDED.category, title = EXCLUDED.title, methodology = EXCLUDED.methodology,
  rules_version = EXCLUDED.rules_version, status = EXCLUDED.status,
  description = EXCLUDED.description, value_type = EXCLUDED.value_type, unit = EXCLUDED.unit,
  calculation_source = EXCLUDED.calculation_source, time_window = EXCLUDED.time_window,
  tie_behavior = EXCLUDED.tie_behavior, subject_type = EXCLUDED.subject_type,
  formula = EXCLUDED.formula;
