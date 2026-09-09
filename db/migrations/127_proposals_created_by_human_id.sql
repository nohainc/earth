-- 127_proposals_created_by_human_id.sql
-- Add created_by_human_id to proposals table to track the initiator / owner of proposals.

ALTER TABLE proposals
  ADD COLUMN IF NOT EXISTS created_by_human_id TEXT REFERENCES humans(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS proposals_created_by_human_id_idx ON proposals(created_by_human_id);

-- Backfill legacy proposals without creator to the administrator of the institution or first human
UPDATE proposals p
SET created_by_human_id = COALESCE(
  (SELECT administrator_human_id FROM institutions i WHERE i.id = p.institution_id AND i.administrator_human_id IS NOT NULL LIMIT 1),
  (SELECT human_id FROM ballots b WHERE b.proposal_id = p.id ORDER BY b.created_at ASC LIMIT 1),
  (SELECT id FROM humans ORDER BY created_at ASC LIMIT 1)
)
WHERE p.created_by_human_id IS NULL;
