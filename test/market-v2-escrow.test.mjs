import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync(new URL('../cloudflare/src/market-postgres.ts', import.meta.url), 'utf8');

test('market V2 reserves both buy CREDIT and sell inventory in ESCROW accounts', () => {
  assert.match(source, /ensureMarketEscrow/);
  assert.match(source, /VALUES \(\$1,\$2,6,0/);
  assert.match(source, /market_sell_escrow/);
  assert.match(source, /market_order_reservation/);
  assert.match(source, /earth_post_transaction/);
});

test('market V2 settlement posts CREDIT and commodity legs atomically', () => {
  assert.match(source, /marketEntries/);
  assert.match(source, /market_trade/);
  assert.match(source, /assetId: 1/);
  assert.match(source, /assetIds\[product\]/);
  assert.match(source, /market-cancel/);
  assert.match(source, /market_order_cancel_refund/);
});

test('market remains the only path using its legacy transfer primitives for dual-write compatibility', () => {
  assert.match(source, /transferCredits/);
  assert.match(source, /mutateResourceBalance/);
});
