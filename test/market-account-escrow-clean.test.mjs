import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(file, 'utf8');
const schema = read('db/baseline/01_schema.sql');
const functions = read('db/baseline/02_functions.sql');
const escrow = read('cloudflare/src/market-escrow.ts');
const market = read('cloudflare/src/market-postgres.ts');
const scheduler = read('cloudflare/src/market-scheduler.ts');

test('market custody uses one shared House+asset escrow account with order reservations', () => {
  assert.match(schema, /CREATE TABLE market_order_reservations/);
  assert.match(schema, /UNIQUE \(order_id, asset_id\)/);
  assert.match(escrow, /accountType\?: 'WALLET' \| 'INVENTORY' \| 'MARKET_ESCROW'/);
  assert.match(escrow, /ON CONFLICT \(owner_economic_id, asset_id, account_type\) DO NOTHING/);
  assert.match(escrow, /INSERT INTO market_order_reservations/);
  assert.doesNotMatch(escrow, /closeEscrowAccount|legacy_account_id|is_default_settlement|account_type = [0-9]/);
});

test('market access is database-enforced as House-only and runtime uses clean order columns', () => {
  assert.match(functions, /CREATE OR REPLACE FUNCTION earth_validate_market_order_owner/);
  assert.match(functions, /IF v_owner_type <> 'HOUSE'/);
  assert.match(functions, /CREATE TRIGGER market_orders_house_owner_integrity/);
  for (const legacy of ['human_id', 'reserved_quote_units', 'reserved_base_units', 'filled_quantity_units', 'is_default_settlement', 'legacy_account_id']) {
    assert.doesNotMatch(market, new RegExp(`\\b${legacy}\\b`));
    assert.doesNotMatch(escrow, new RegExp(`\\b${legacy}\\b`));
    assert.doesNotMatch(scheduler, new RegExp(`\\b${legacy}\\b`));
  }
  assert.match(escrow, /market_order_reservations/);
  assert.match(market, /status IN \('OPEN','PARTIAL'\)/);
});
