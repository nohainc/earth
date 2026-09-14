import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync(new URL('../cloudflare/src/resource-ledger-postgres.ts', import.meta.url), 'utf8');
const estate = fs.readFileSync(new URL('../cloudflare/src/real-estate-postgres.ts', import.meta.url), 'utf8');

test('simple resource mutations have a V2 double-entry bridge and legacy projection sync', () => {
  assert.match(source, /export async function postEconomicResourceMutation/);
  assert.match(source, /o\.economic_id = \$2/);
  assert.match(source, /earth_post_transaction/);
  assert.match(source, /mutateResourceBalanceInTransaction/);
  assert.match(estate, /postEconomicResourceMutation/);
  assert.doesNotMatch(estate, /mutateResourceBalance/);
});

test('market uses the canonical escrow bridge and resource semantics are explicit', () => {
  assert.match(fs.readFileSync(new URL('../cloudflare/src/market-postgres.ts', import.meta.url), 'utf8'), /reserveForOrder/);
  assert.match(source, /RESOURCE_PRODUCTION/);
  assert.match(source, /RESOURCE_CONSUMPTION/);
});
