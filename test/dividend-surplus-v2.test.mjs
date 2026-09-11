import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(new URL('../db/migrations/224_dividend_surplus_controls.sql', import.meta.url), 'utf8');
const engine = fs.readFileSync(new URL('../cloudflare/src/civic-dividend-engine.ts', import.meta.url), 'utf8');

test('dividends record surplus controls and post one V2 batch', () => {
  assert.match(migration, /dividend_settlement_runs/);
  for (const field of ['committed_obligations_units', 'required_reserve_units', 'distributable_units', 'economic_transaction_id']) assert.match(migration, new RegExp(field));
  assert.match(engine, /earth_post_settlement_batch/);
  assert.match(engine, /tax_obligations/);
  assert.match(engine, /bank_loans/);
  assert.match(engine, /institution_budgets/);
  assert.doesNotMatch(engine, /postEconomicCreditTransfer|transferCredits/);
});
