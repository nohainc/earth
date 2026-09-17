-- EARTH ACTIVE MIGRATION: V5 policy governance and future-effective activation.

CREATE TABLE v5_governance_proposals (
  id TEXT PRIMARY KEY,
  subject_type TEXT NOT NULL CHECK (subject_type IN ('EARTH','CORPORATION')),
  subject_id TEXT,
  action_type TEXT NOT NULL CHECK (action_type IN ('EARTH_CAPACITY_POLICY','CORPORATION_HOUSE_RATE','PROGRESSIVE_SCHEDULE','CORPORATION_ADMISSION_POLICY')),
  payload JSONB NOT NULL CHECK (jsonb_typeof(payload) = 'object'),
  status TEXT NOT NULL DEFAULT 'VOTING' CHECK (status IN ('VOTING','PASSED','REJECTED','EXECUTED','FAILED')),
  submitted_game_day BIGINT NOT NULL CHECK (submitted_game_day >= 1),
  voting_start_game_day BIGINT NOT NULL,
  voting_end_game_day BIGINT NOT NULL,
  effective_from_game_day BIGINT NOT NULL,
  support_votes INTEGER NOT NULL DEFAULT 0 CHECK (support_votes >= 0),
  oppose_votes INTEGER NOT NULL DEFAULT 0 CHECK (oppose_votes >= 0),
  quorum_met BOOLEAN,
  created_by_human_id TEXT NOT NULL REFERENCES humans(id),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK ((subject_type = 'EARTH' AND subject_id IS NULL) OR (subject_type = 'CORPORATION' AND subject_id IS NOT NULL)),
  CHECK (voting_start_game_day >= submitted_game_day AND voting_end_game_day >= voting_start_game_day),
  CHECK (effective_from_game_day > submitted_game_day)
);

CREATE TABLE v5_governance_ballots (
  proposal_id TEXT NOT NULL REFERENCES v5_governance_proposals(id),
  house_id TEXT NOT NULL REFERENCES houses(id),
  cast_by_human_id TEXT NOT NULL REFERENCES humans(id),
  choice TEXT NOT NULL CHECK (choice IN ('SUPPORT','OPPOSE','ABSTAIN')),
  cast_game_day BIGINT NOT NULL CHECK (cast_game_day >= 1),
  correlation_id TEXT NOT NULL UNIQUE,
  PRIMARY KEY (proposal_id, house_id)
);

CREATE TABLE v5_governance_activation_queue (
  proposal_id TEXT PRIMARY KEY REFERENCES v5_governance_proposals(id),
  action_type TEXT NOT NULL,
  payload JSONB NOT NULL CHECK (jsonb_typeof(payload) = 'object'),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 1),
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','APPLIED','FAILED')),
  applied_game_day BIGINT,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE v5_corporation_admission_policy_versions (
  id TEXT PRIMARY KEY,
  corporation_id TEXT NOT NULL REFERENCES corporations(id),
  version INTEGER NOT NULL CHECK (version > 0),
  admission_policy TEXT NOT NULL CHECK (admission_policy IN ('OPEN','APPROVAL','INVITE_ONLY')),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 1),
  effective_to_game_day BIGINT,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('DRAFT','ACTIVE','RETIRED')),
  proposal_id TEXT REFERENCES v5_governance_proposals(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (corporation_id, version),
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day)
);

CREATE INDEX v5_governance_proposals_subject_idx ON v5_governance_proposals(subject_type, subject_id, status, voting_end_game_day);
CREATE INDEX v5_governance_activation_due_idx ON v5_governance_activation_queue(status, effective_from_game_day);
