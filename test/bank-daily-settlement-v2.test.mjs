import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(new URL('../db/migrations/219_v2_bank_daily_settlement.sql', import.meta.url), 'utf8');
const engine = fs.readFileSync(new URL('../cloudflare/src/global-bank-settlement-engine.ts', import.meta.url), 'utf8');

test('daily bank settlement is set-based and Economy V2-only', () => {
  assert.match(migration, /CREATE TABLE IF NOT EXISTS bank_settlement_journals/);
  assert.match(migration, /earth_settle_v2_global_bank/);
  assert.match(migration, /earth_accrue_bank_interest/);
  assert.match(migration, /earth_post_settlement_batch/);
  assert.match(migration, /v2_bank_loan_due/);
  assert.match(migration, /v2_bank_deposit_due/);
  assert.match(migration, /SUM\(payout_units\)/);
  assert.match(migration, /LIQUIDITY_CONSTRAINED/);
  assert.doesNotMatch(engine, /account_balances|resource_balances|global_bank_loans|global_bank_deposits/);
  assert.match(engine, /earth_settle_v2_global_bank/);
  assert.doesNotMatch(engine, /for \(/i);
});
