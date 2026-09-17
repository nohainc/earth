-- EARTH ACTIVE MIGRATION: freeze the exact V4 House electorate at voting start.

CREATE TABLE IF NOT EXISTS governance_electorate_snapshots_v4 (
  proposal_id TEXT NOT NULL REFERENCES governance_proposals_v4(id),
  house_id TEXT NOT NULL REFERENCES houses(id),
  snapshot_game_day BIGINT NOT NULL CHECK (snapshot_game_day >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (proposal_id, house_id)
);

CREATE INDEX IF NOT EXISTS governance_electorate_snapshots_v4_house_idx
  ON governance_electorate_snapshots_v4 (house_id, proposal_id);
