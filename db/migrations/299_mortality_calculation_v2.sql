-- Mortality V2: make the deterministic world seed explicit.
ALTER TABLE world_state
  ADD COLUMN IF NOT EXISTS world_seed TEXT NOT NULL DEFAULT 'EARTH-WORLD-V2';

COMMENT ON COLUMN world_state.world_seed IS
  'Stable seed used for replayable game randomness; changing it starts a new simulation identity.';
