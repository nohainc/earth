-- Store the exact game-clock minute for bank deposit lifecycle timestamps.

ALTER TABLE global_bank_deposits
  ADD COLUMN IF NOT EXISTS start_game_minute INTEGER NOT NULL DEFAULT 0
    CHECK (start_game_minute BETWEEN 0 AND 1439),
  ADD COLUMN IF NOT EXISTS maturity_game_minute INTEGER NOT NULL DEFAULT 0
    CHECK (maturity_game_minute BETWEEN 0 AND 1439);

