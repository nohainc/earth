import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('Market V2 controls orders and self-trade ownership by House economic owner', () => {
  const market = read('cloudflare/src/market-postgres.ts');
  const escrow = read('cloudflare/src/market-escrow.ts');
  const api = read('cloudflare/src/market-api.ts');
  const migration = read('db/migrations/301_market_house_continuity.sql');

  assert.match(market, /owner_economic_id = \(SELECT owner\.economic_id FROM humans/);
  assert.match(market, /ownerId: String\(row\.owner_economic_id\)/);
  assert.match(escrow, /SELECT house_id FROM humans WHERE id = \$1/);
  assert.match(api, /JOIN owner_registry owner ON owner\.economic_id = market_orders\.owner_economic_id/);
  assert.match(migration, /market_orders_owner_correlation_idx/);
  assert.doesNotMatch(market, /UPDATE market_orders SET status = 'cancelled'[\s\S]{0,200}human_id = \$2/);
});
