-- Building domain configuration: explicit, extensible catalog effects.
-- Runtime services must sum these rows instead of deriving zoning/capacity from
-- building type names or tier formulas.

CREATE TABLE IF NOT EXISTS building_catalog_effects (
  catalog_id TEXT NOT NULL REFERENCES building_catalog(id) ON DELETE CASCADE,
  effect_code TEXT NOT NULL,
  effect_value BIGINT NOT NULL CHECK (effect_value >= 0),
  rules_version TEXT NOT NULL DEFAULT 'building-effects-v1',
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (catalog_id, effect_code, rules_version)
);

CREATE INDEX IF NOT EXISTS building_catalog_effects_code_idx
  ON building_catalog_effects (effect_code, catalog_id);

INSERT INTO building_catalog_effects (catalog_id, effect_code, effect_value)
SELECT id, 'CITY_CITIZEN_CAPACITY', 10
FROM building_catalog
WHERE building_type = 'urban-district-module' AND tier = 1
ON CONFLICT (catalog_id, effect_code, rules_version) DO NOTHING;

INSERT INTO building_catalog_effects (catalog_id, effect_code, effect_value)
SELECT id, 'CITY_TOTAL_SLOTS', 120
FROM building_catalog
WHERE building_type = 'urban-district-module' AND tier = 1
ON CONFLICT (catalog_id, effect_code, rules_version) DO NOTHING;

INSERT INTO building_catalog_effects (catalog_id, effect_code, effect_value)
SELECT id, 'CITY_CIVIC_RESERVED_SLOTS', 20
FROM building_catalog
WHERE building_type = 'urban-district-module' AND tier = 1
ON CONFLICT (catalog_id, effect_code, rules_version) DO NOTHING;

INSERT INTO building_catalog_effects (catalog_id, effect_code, effect_value)
SELECT id, 'PRIVATE_OWNER_SLOTS', tier * 10
FROM building_catalog
WHERE building_type = 'private-estate-plot'
ON CONFLICT (catalog_id, effect_code, rules_version) DO NOTHING;
