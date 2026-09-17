-- EARTH ACTIVE MIGRATION: persist the exact V5 House electorate at voting start.

CREATE TABLE v5_governance_electorate_snapshots_v5 (
  proposal_id TEXT NOT NULL REFERENCES v5_governance_proposals(id),
  house_id TEXT NOT NULL REFERENCES houses(id),
  snapshot_game_day BIGINT NOT NULL CHECK (snapshot_game_day >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (proposal_id, house_id)
);

CREATE INDEX v5_governance_electorate_snapshots_house_idx
  ON v5_governance_electorate_snapshots_v5 (house_id, proposal_id);
