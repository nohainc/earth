CREATE UNIQUE INDEX IF NOT EXISTS authority_events_transition_idx ON authority_events(human_id, role_id, action, game_day);
