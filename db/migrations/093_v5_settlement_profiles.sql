-- EARTH ACTIVE MIGRATION: V5 structural settlement profiles.
-- Profiles are rebuildable materialized facts; canonical ownership and
-- building rows remain authoritative.

CREATE TABLE v5_house_settlement_profiles (
  house_id TEXT PRIMARY KEY REFERENCES houses(id),
  corporation_id TEXT REFERENCES corporations(id),
  residential_capacity_units BIGINT NOT NULL DEFAULT 1 CHECK (residential_capacity_units = 1),
  productive_capacity_units BIGINT NOT NULL DEFAULT 0 CHECK (productive_capacity_units >= 0),
  total_capacity_units BIGINT NOT NULL DEFAULT 1 CHECK (total_capacity_units = residential_capacity_units + productive_capacity_units),
  active_building_count INTEGER NOT NULL DEFAULT 0 CHECK (active_building_count >= 0),
  profile_version TEXT NOT NULL,
  source_game_day BIGINT NOT NULL CHECK (source_game_day >= 1),
  dirty BOOLEAN NOT NULL DEFAULT FALSE,
  dirty_reason TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE v5_corporation_settlement_profiles (
  corporation_id TEXT PRIMARY KEY REFERENCES corporations(id),
  active_member_count INTEGER NOT NULL DEFAULT 0 CHECK (active_member_count >= 0),
  member_residential_capacity_units BIGINT NOT NULL DEFAULT 0 CHECK (member_residential_capacity_units >= 0),
  member_productive_capacity_units BIGINT NOT NULL DEFAULT 0 CHECK (member_productive_capacity_units >= 0),
  public_capacity_units BIGINT NOT NULL DEFAULT 0 CHECK (public_capacity_units >= 0),
  total_occupied_capacity_units BIGINT NOT NULL DEFAULT 0 CHECK (total_occupied_capacity_units = member_residential_capacity_units + member_productive_capacity_units + public_capacity_units),
  active_public_building_count INTEGER NOT NULL DEFAULT 0 CHECK (active_public_building_count >= 0),
  profile_version TEXT NOT NULL,
  source_game_day BIGINT NOT NULL CHECK (source_game_day >= 1),
  dirty BOOLEAN NOT NULL DEFAULT FALSE,
  dirty_reason TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX v5_house_settlement_profiles_corporation_idx
  ON v5_house_settlement_profiles (corporation_id, house_id);
CREATE INDEX v5_house_settlement_profiles_rebuild_idx
  ON v5_house_settlement_profiles (dirty, profile_version, house_id);
CREATE INDEX v5_corporation_settlement_profiles_rebuild_idx
  ON v5_corporation_settlement_profiles (dirty, profile_version, corporation_id);

-- Seed the materialized layer atomically from canonical facts so the first
-- post-migration API read does not depend on a scheduler run having happened.
INSERT INTO v5_house_settlement_profiles
  (house_id, corporation_id, residential_capacity_units, productive_capacity_units,
   total_capacity_units, active_building_count, profile_version, source_game_day)
SELECT h.id, ha.corporation_id, 1,
       COALESCE(SUM(bc.slot_footprint), 0),
       1 + COALESCE(SUM(bc.slot_footprint), 0),
       COUNT(b.id)::INTEGER, 'v5-structural-capacity-1',
       GREATEST(1, COALESCE((SELECT game_day FROM world_state WHERE id = 'WORLD'), 1))
  FROM houses h
  LEFT JOIN house_affiliations ha ON ha.house_id = h.id AND ha.status = 'ACTIVE'
  LEFT JOIN owner_registry o ON o.id = h.id AND o.owner_type = 'HOUSE'
  LEFT JOIN buildings b ON b.owner_economic_id = o.economic_id AND b.status = 'ACTIVE'
  LEFT JOIN building_catalog bc ON bc.id = b.catalog_id
 GROUP BY h.id, ha.corporation_id
 ON CONFLICT (house_id) DO NOTHING;

INSERT INTO v5_corporation_settlement_profiles
  (corporation_id, active_member_count, member_residential_capacity_units,
   member_productive_capacity_units, public_capacity_units,
   total_occupied_capacity_units, active_public_building_count,
   profile_version, source_game_day)
SELECT c.id, COUNT(hp.house_id)::INTEGER,
       COALESCE(SUM(hp.residential_capacity_units), 0),
       COALESCE(SUM(hp.productive_capacity_units), 0),
       COALESCE((SELECT SUM(bc.slot_footprint)
                   FROM buildings b
                   JOIN building_catalog bc ON bc.id = b.catalog_id
                   JOIN owner_registry o ON o.economic_id = b.owner_economic_id
                                        AND o.owner_type = 'CORPORATION'
                                        AND o.id = c.id
                  WHERE b.status = 'ACTIVE' AND bc.ownership_scope = 'PUBLIC'), 0),
       COALESCE(SUM(hp.total_capacity_units), 0) +
       COALESCE((SELECT SUM(bc.slot_footprint)
                   FROM buildings b
                   JOIN building_catalog bc ON bc.id = b.catalog_id
                   JOIN owner_registry o ON o.economic_id = b.owner_economic_id
                                        AND o.owner_type = 'CORPORATION'
                                        AND o.id = c.id
                  WHERE b.status = 'ACTIVE' AND bc.ownership_scope = 'PUBLIC'), 0),
       COALESCE((SELECT COUNT(*)
                   FROM buildings b
                   JOIN building_catalog bc ON bc.id = b.catalog_id
                   JOIN owner_registry o ON o.economic_id = b.owner_economic_id
                                        AND o.owner_type = 'CORPORATION'
                                        AND o.id = c.id
                  WHERE b.status = 'ACTIVE' AND bc.ownership_scope = 'PUBLIC'), 0)::INTEGER,
       'v5-structural-capacity-1',
       GREATEST(1, COALESCE((SELECT game_day FROM world_state WHERE id = 'WORLD'), 1))
  FROM corporations c
  LEFT JOIN v5_house_settlement_profiles hp ON hp.corporation_id = c.id
 GROUP BY c.id
 ON CONFLICT (corporation_id) DO NOTHING;
