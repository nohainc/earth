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
