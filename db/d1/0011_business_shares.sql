CREATE TABLE IF NOT EXISTS business_shares (
  business_id TEXT NOT NULL REFERENCES businesses(id),
  holder_id TEXT NOT NULL REFERENCES humans(id),
  shares INTEGER NOT NULL CHECK (shares > 0),
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (business_id, holder_id)
);

CREATE INDEX IF NOT EXISTS business_shares_holder_idx ON business_shares(holder_id);

INSERT OR IGNORE INTO business_shares (business_id, holder_id, shares)
VALUES ('B-1048', 'H-0044', 100);
