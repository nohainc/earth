import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync(new URL('../cloudflare/src/resource-ledger-postgres.ts', import.meta.url), 'utf8');
const estate = fs.readFileSync(new URL('../cloudflare/src/real-estate-postgres.ts', import.meta.url), 'utf8');

test('simple resource mutations have a V2 double-entry bridge and legacy projection sync', () => {
  assert.match(source, /export async function postEconomicResourceMutation/);
  assert.match(source, /account_type = \$2/);
  assert.match(source, /earth_post_transaction/);
  assert.match(source, /mutateResourceBalanceInTransaction/);
  assert.match(estate, /postEconomicResourceMutation/);
  assert.doesNotMatch(estate, /mutateResourceBalance/);
});

test('market remains on the compatibility path while life maintenance uses the V2 bridge', () => {
  assert.match(fs.readFileSync(new URL('../cloudflare/src/market-postgres.ts', import.meta.url), 'utf8'), /mutateResourceBalance/);
  assert.match(fs.readFileSync(new URL('../cloudflare/src/life-maintenance-postgres.ts', import.meta.url), 'utf8'), /postEconomicResourceMutation/);
});
