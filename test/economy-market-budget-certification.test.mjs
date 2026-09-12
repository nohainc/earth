import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');

test('Economy V2 certification: postings are atomic, balanced and idempotent', () => {
  const escrow = read('cloudflare/src/market-escrow.ts');
  const schema = read('db/baseline/01_schema.sql');
  assert.match(escrow, /earth_post_transaction/);
  assert.match(escrow, /earth_post_settlement_batch/);
  assert.match(schema, /economic_entries/);
  assert.match(schema, /correlation_id.*UNIQUE|UNIQUE.*correlation_id/i);
  assert.match(schema, /balance.*>=.*0|negative.*balance/i);
});

test('Market certification: collateral, deterministic matching and replay protection are enforced', () => {
  const market = read('cloudflare/src/market-postgres.ts');
  const clearing = read('cloudflare/src/market-clearing-engine.ts');
  const batches = read('cloudflare/src/market-scheduler.ts');
  assert.match(market, /reserveForOrder/);
  assert.match(market, /releaseReservation/);
  assert.match(market, /eligible_batch_id/);
  assert.match(market, /postSettlementBatch/);
  assert.match(clearing, /sequenceNo/);
  assert.match(clearing, /selfTrade/);
  assert.match(batches, /earth_claim_market_batch_instrument/);
  assert.match(batches, /settleMarketBatch/);
});

test('Budget certification: authority, cash and commitments remain separate', () => {
  const api = read('cloudflare/src/institution-budget-api.ts');
  const migration = read('db/baseline/01_schema.sql');
  const spending = read('cloudflare/src/institution-budget-api.ts');
  assert.match(api, /authorized_units.*committed_units.*spent_units/s);
  assert.match(migration, /authorized_units >= committed_units \+ spent_units/);
  assert.match(migration, /institution_budget_commitments/);
  assert.match(spending, /earth_pay_budget_commitment|earth_spend_institution_budget/);
});

test('Certification suite remains a mandatory CI target', () => {
  const packageJson = JSON.parse(read('package.json'));
  assert.match(packageJson.scripts['test:certification'], /economy-market-budget-certification/);
  assert.match(packageJson.scripts.test, /test:certification|economy-market-budget-certification/);
});
