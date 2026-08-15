CREATE TABLE IF NOT EXISTS ownership_events (
  id TEXT PRIMARY KEY,
  asset_type TEXT NOT NULL,
  asset_id TEXT NOT NULL,
  from_owner_id TEXT,
  to_owner_id TEXT NOT NULL,
  quantity NUMERIC NOT NULL DEFAULT 1 CHECK (quantity > 0),
  reason_type TEXT NOT NULL,
  reason_id TEXT,
  game_day INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ownership_events_asset_idx ON ownership_events(asset_type, asset_id, game_day DESC);
CREATE INDEX IF NOT EXISTS ownership_events_owner_idx ON ownership_events(to_owner_id, game_day DESC);

INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day)
SELECT 'BACKFILL-MACHINE-' || id, 'MACHINE', id, NULL, owner_id, 1, 'historical_backfill', id, 0
FROM machines
WHERE NOT EXISTS (SELECT 1 FROM ownership_events WHERE asset_type = 'MACHINE' AND asset_id = machines.id);
INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day)
SELECT 'BACKFILL-BUSINESS-' || id, 'BUSINESS', id, NULL, owner_id, 1, 'historical_backfill', id, 0
FROM businesses
WHERE NOT EXISTS (SELECT 1 FROM ownership_events WHERE asset_type = 'BUSINESS' AND asset_id = businesses.id);
INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day)
SELECT 'BACKFILL-SHARES-' || business_id || '-' || holder_id, 'BUSINESS_SHARES', business_id, NULL, holder_id, shares, 'historical_backfill', business_id, 0
FROM business_shares
WHERE NOT EXISTS (SELECT 1 FROM ownership_events WHERE asset_type = 'BUSINESS_SHARES' AND asset_id = business_shares.business_id AND to_owner_id = business_shares.holder_id);
