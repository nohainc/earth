import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('Spot orders carry policy provenance and bounded expiry without changing matcher authority', () => {
  const migration = fs.readFileSync('db/migrations/024_market_policy_orders.sql', 'utf8');
  const market = fs.readFileSync('cloudflare/src/market-postgres.ts', 'utf8');
  const scheduler = fs.readFileSync('cloudflare/src/market-scheduler.ts', 'utf8');
  const policy = fs.readFileSync('cloudflare/src/house-policy-execution.ts', 'utf8');
  assert.match(migration, /source_type TEXT NOT NULL DEFAULT 'MANUAL'/);
  assert.match(migration, /policy_id TEXT REFERENCES house_operating_policies/);
  assert.match(migration, /good_til_game_day BIGINT/);
  assert.match(market, /sourceType\?: 'MANUAL' \| 'HOUSE_POLICY'/);
  assert.match(market, /expireMarketOrders/);
  assert.match(scheduler, /expireMarketOrders/);
  assert.match(policy, /sourceType: 'HOUSE_POLICY'/);
  assert.match(policy, /goodTilGameDay: gameDay \+ 1/);
});
