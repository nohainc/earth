-- 024_communications_and_dispatch.sql
-- Migration 024: Universal Comm-Link Frequency Channels & Diplomatic Dispatch System

CREATE TABLE IF NOT EXISTS comm_channels (
    id TEXT PRIMARY KEY,
    scope TEXT NOT NULL CHECK (scope IN ('global', 'city', 'institution', 'direct')),
    scope_id TEXT,
    name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS comm_messages (
    id TEXT PRIMARY KEY,
    channel_id TEXT NOT NULL REFERENCES comm_channels(id) ON DELETE CASCADE,
    sender_human_id TEXT NOT NULL REFERENCES humans(id) ON DELETE CASCADE,
    sender_display_name TEXT NOT NULL,
    sender_dynasty_name TEXT,
    body TEXT NOT NULL,
    game_day INT NOT NULL DEFAULT 1,
    game_minute INT NOT NULL DEFAULT 0,
    attachments JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS diplomatic_dispatches (
    id TEXT PRIMARY KEY,
    sender_human_id TEXT NOT NULL REFERENCES humans(id) ON DELETE CASCADE,
    recipient_human_id TEXT NOT NULL REFERENCES humans(id) ON DELETE CASCADE,
    subject TEXT NOT NULL,
    body TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'unread' CHECK (status IN ('unread', 'read', 'archived')),
    game_day INT NOT NULL DEFAULT 1,
    game_minute INT NOT NULL DEFAULT 0,
    dispatch_type TEXT NOT NULL DEFAULT 'diplomatic' CHECK (dispatch_type IN ('diplomatic', 'contract_offer', 'patent_license', 'merger_tender', 'succession_notice')),
    action_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    read_at TIMESTAMPTZ
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS comm_messages_channel_idx ON comm_messages (channel_id, game_day DESC, created_at DESC);
CREATE INDEX IF NOT EXISTS diplomatic_dispatches_recipient_idx ON diplomatic_dispatches (recipient_human_id, status, game_day DESC);
CREATE INDEX IF NOT EXISTS diplomatic_dispatches_sender_idx ON diplomatic_dispatches (sender_human_id, created_at DESC);

-- Seed global channels if not present
INSERT INTO comm_channels (id, scope, scope_id, name, description)
VALUES 
    ('channel-global-relay', 'global', NULL, 'Planetary Public Relay', 'Universal broadcast frequency for open civilizational discourse and market news.'),
    ('channel-city-new-tokyo', 'city', 'city-new-tokyo', 'Neo-Tokyo City Hall', 'Municipal forum for Neo-Tokyo residents, tax debates, and infrastructure initiatives.'),
    ('channel-city-new-york', 'city', 'city-new-york', 'New York Municipal Council', 'Municipal chamber for New York residents and commercial policy.'),
    ('channel-city-london', 'city', 'city-london', 'London Industrial Forum', 'Municipal chamber for London residents, trade, and industrial supply.'),
    ('channel-city-geneva', 'city', 'city-geneva', 'Geneva Assembly Hall', 'Municipal chamber for Geneva residents and constitutional jurisprudence.'),
    ('channel-city-singapore', 'city', 'city-singapore', 'Singapore Maritime Exchange', 'Municipal forum for Singapore logistics, freight, and trade.')
ON CONFLICT (id) DO NOTHING;
