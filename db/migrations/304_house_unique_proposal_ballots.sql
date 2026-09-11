-- Death & succession V2: a House may cast at most one ballot per proposal.
-- human_id remains the historical Human who actually submitted the vote.

ALTER TABLE ballots
  ADD COLUMN IF NOT EXISTS house_id TEXT REFERENCES houses(id);

UPDATE ballots b
SET house_id = h.house_id
FROM humans h
WHERE h.id = b.human_id
  AND b.house_id IS NULL;

-- Preserve the earliest recorded vote if development data contains duplicate
-- ballots from successive Humans representing the same House.
DELETE FROM ballots newer
USING ballots older
WHERE newer.proposal_id = older.proposal_id
  AND newer.house_id IS NOT NULL
  AND newer.house_id = older.house_id
  AND newer.ctid > older.ctid;

ALTER TABLE ballots
  ALTER COLUMN house_id SET NOT NULL;

ALTER TABLE ballots DROP CONSTRAINT IF EXISTS ballots_pkey;
ALTER TABLE ballots ADD CONSTRAINT ballots_pkey PRIMARY KEY (proposal_id, house_id);

CREATE INDEX IF NOT EXISTS ballots_human_audit_idx ON ballots(human_id, created_at DESC);
