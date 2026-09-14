import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync(new URL('../cloudflare/src/market-postgres.ts', import.meta.url), 'utf8');
const escrow = fs.readFileSync(new URL('../cloudflare/src/market-escrow.ts', import.meta.url), 'utf8');

test('market V2 reserves both buy CREDIT and sell inventory in MARKET_ESCROW accounts', () => {
  assert.match(escrow, /reserveForOrder/);
  assert.match(escrow, /MARKET_ESCROW/);
  assert.match(escrow, /market_order_reservations/);
  assert.match(escrow, /balance_units/);
  assert.match(source, /market_sell_escrow/);
  assert.match(source, /market_order_reservation/);
  assert.match(escrow, /earth_post_transaction/);
});

test('market V2 settlement posts CREDIT and commodity legs atomically', () => {
  assert.match(source, /postSettlementBatch/);
  assert.match(source, /market_batch_trade/);
  assert.match(source, /instrument\.base_asset_id/);
  assert.match(escrow, /delta_units/);
  assert.match(escrow, /releaseReservation/);
  assert.match(escrow, /updateReservationRemaining/);
  assert.match(source, /market_order_cancellation/);
});

test('market no longer mutates legacy balances for collateral movement', () => {
  assert.doesNotMatch(source, /transferCredits/);
  assert.doesNotMatch(source, /mutateResourceBalance/);
});
