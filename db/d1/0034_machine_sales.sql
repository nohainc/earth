CREATE TABLE IF NOT EXISTS machine_sales (
  id TEXT PRIMARY KEY,
  machine_id TEXT NOT NULL REFERENCES machines(id),
  seller_id TEXT NOT NULL REFERENCES humans(id),
  buyer_id TEXT NOT NULL REFERENCES humans(id),
  price NUMERIC NOT NULL CHECK (price > 0),
  game_day INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS machine_sales_participant_idx
  ON machine_sales(seller_id, buyer_id, game_day DESC);
