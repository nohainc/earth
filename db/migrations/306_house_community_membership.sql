-- Death & Continuity V2 Plan 18.
-- Community membership follows the persistent House; human_id identifies the
-- current representative for display and historical membership events.

ALTER TABLE community_members
  ADD COLUMN IF NOT EXISTS house_id TEXT REFERENCES houses(id);

UPDATE community_members cm
SET house_id = h.house_id
FROM humans h
WHERE h.id = cm.human_id
  AND cm.house_id IS NULL;

DELETE FROM community_members newer
USING community_members older
WHERE newer.community_id = older.community_id
  AND newer.house_id IS NOT NULL
  AND newer.house_id = older.house_id
  AND newer.ctid > older.ctid;

ALTER TABLE community_members
  ALTER COLUMN house_id SET NOT NULL;

ALTER TABLE community_members DROP CONSTRAINT IF EXISTS community_members_pkey;
ALTER TABLE community_members ADD CONSTRAINT community_members_pkey PRIMARY KEY (community_id, house_id);

CREATE INDEX IF NOT EXISTS community_members_house_idx ON community_members(house_id, community_id);
CREATE INDEX IF NOT EXISTS community_members_human_idx ON community_members(human_id, community_id);
