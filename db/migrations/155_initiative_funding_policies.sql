-- EARTH ACTIVE MIGRATION: versioned Initiative funding and matching policy.

CREATE TABLE IF NOT EXISTS initiative_funding_policies (
  id TEXT PRIMARY KEY,
  version INTEGER NOT NULL CHECK (version > 0),
  code TEXT NOT NULL CHECK (code IN ('NONE','LINEAR_MATCH','BREADTH_MATCH')),
  match_rate_bps INTEGER NOT NULL CHECK (match_rate_bps BETWEEN 0 AND 10000),
  breadth_bonus_bps_per_supporter INTEGER NOT NULL DEFAULT 0 CHECK (breadth_bonus_bps_per_supporter >= 0),
  breadth_supporter_cap INTEGER NOT NULL DEFAULT 0 CHECK (breadth_supporter_cap >= 0),
  max_house_contribution_units BIGINT NOT NULL CHECK (max_house_contribution_units > 0),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','RETIRED')),
  rules_version TEXT NOT NULL,
  UNIQUE (code, version)
);

INSERT INTO initiative_funding_policies
  (id, version, code, match_rate_bps, breadth_bonus_bps_per_supporter,
   breadth_supporter_cap, max_house_contribution_units, rules_version)
VALUES
  ('INITIATIVE-POLICY-NONE-V1', 1, 'NONE', 0, 0, 0, 10000, 'initiative-funding-v1'),
  ('INITIATIVE-POLICY-LINEAR-MATCH-V1', 1, 'LINEAR_MATCH', 10000, 0, 0, 10000, 'initiative-funding-v1'),
  ('INITIATIVE-POLICY-BREADTH-MATCH-V1', 1, 'BREADTH_MATCH', 10000, 25, 100, 10000, 'initiative-funding-v1')
ON CONFLICT (id) DO NOTHING;

UPDATE v5_initiatives SET matching_policy = 'LINEAR_MATCH' WHERE matching_policy = 'LINEAR';
UPDATE v5_initiatives SET matching_policy = 'BREADTH_MATCH' WHERE matching_policy = 'BREADTH';
ALTER TABLE v5_initiatives ADD COLUMN IF NOT EXISTS funding_policy_id TEXT;
UPDATE v5_initiatives
   SET funding_policy_id = CASE matching_policy
     WHEN 'LINEAR_MATCH' THEN 'INITIATIVE-POLICY-LINEAR-MATCH-V1'
     WHEN 'BREADTH_MATCH' THEN 'INITIATIVE-POLICY-BREADTH-MATCH-V1'
     ELSE 'INITIATIVE-POLICY-NONE-V1'
   END
 WHERE funding_policy_id IS NULL;
ALTER TABLE v5_initiatives ALTER COLUMN funding_policy_id SET NOT NULL;
ALTER TABLE v5_initiatives ADD CONSTRAINT v5_initiatives_funding_policy_fk FOREIGN KEY (funding_policy_id) REFERENCES initiative_funding_policies(id);
