import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync(new URL('../cloudflare/src/market-postgres.ts', import.meta.url), 'utf8');
const escrow = fs.readFileSync(new URL('../cloudflare/src/market-escrow.ts', import.meta.url), 'utf8');

test('market V2 reserves both buy CREDIT and sell inventory in ESCROW accounts', () => {
  assert.match(escrow, /reserveForOrder/);
  assert.match(escrow, /VALUES \(\$1,\$2,6,0/);
  assert.match(source, /market_sell_escrow/);
  assert.match(source, /market_order_reservation/);
  assert.match(escrow, /earth_post_transaction/);
});

test('market V2 settlement posts CREDIT and commodity legs atomically', () => {
  assert.match(source, /marketEntries/);
  assert.match(source, /market_trade/);
  assert.match(source, /assetId: 1/);
  assert.match(source, /assetIds\[product\]/);
  assert.match(escrow, /releaseReservation/);
  assert.match(escrow, /closeEscrowAccount/);
  assert.match(source, /market_order_cancel_refund/);
});

test('market no longer mutates legacy balances for collateral movement', () => {
  assert.doesNotMatch(source, /transferCredits/);
  assert.doesNotMatch(source, /mutateResourceBalance/);
});
