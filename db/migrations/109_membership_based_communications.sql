-- Migration 109: membership-based organization chats and global private messages.

ALTER TABLE comm_channels ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE comm_channels DROP CONSTRAINT IF EXISTS comm_channels_scope_check;
DELETE FROM comm_channels WHERE scope = 'institution';
ALTER TABLE comm_channels ADD CONSTRAINT comm_channels_scope_check
  CHECK (scope IN ('global', 'city', 'corporation', 'community', 'direct'));

CREATE TABLE IF NOT EXISTS comm_direct_conversations (
  channel_id TEXT PRIMARY KEY REFERENCES comm_channels(id) ON DELETE CASCADE,
  participant_low_id TEXT NOT NULL REFERENCES humans(id) ON DELETE CASCADE,
  participant_high_id TEXT NOT NULL REFERENCES humans(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (participant_low_id <> participant_high_id),
  CHECK (participant_low_id < participant_high_id),
  UNIQUE (participant_low_id, participant_high_id)
);
CREATE INDEX IF NOT EXISTS comm_direct_low_idx
  ON comm_direct_conversations(participant_low_id);
CREATE INDEX IF NOT EXISTS comm_direct_high_idx
  ON comm_direct_conversations(participant_high_id);

INSERT INTO comm_channels (id, scope, scope_id, name, description)
SELECT 'channel-city-' || c.id, 'city', c.id, i.name || ' Chat',
       'Private conversation for current members of ' || i.name || '.'
FROM cities c
JOIN institutions i ON i.id = c.institution_id
WHERE i.status = 'active'
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, description = EXCLUDED.description;

INSERT INTO comm_channels (id, scope, scope_id, name, description)
SELECT 'channel-corporation-' || c.id, 'corporation', c.id, i.name || ' Chat',
       'Private conversation for current members of ' || i.name || '.'
FROM corporations c
JOIN institutions i ON i.id = c.institution_id
WHERE i.status = 'active'
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, description = EXCLUDED.description;

INSERT INTO comm_channels (id, scope, scope_id, name, description)
SELECT 'channel-community-' || c.id, 'community', c.id, c.name || ' Chat',
       'Private conversation for current members of ' || c.name || '.'
FROM communities c
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, description = EXCLUDED.description;
