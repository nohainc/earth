import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(new URL('../db/migrations/215_bank_deposits_v2.sql', import.meta.url), 'utf8');
const client = fs.readFileSync(new URL('../cloudflare/src/global-bank-postgres.ts', import.meta.url), 'utf8');

test('V2 deposits are integer-unit liabilities funded by atomic transfers', () => {
  assert.match(migration, /CREATE TABLE IF NOT EXISTS bank_deposits/);
  for (const field of ['depositor_economic_id', 'principal_units', 'accrued_interest_units', 'rate_bps', 'rate_rule_version', 'start_total_game_minute', 'maturity_total_game_minute', 'created_transaction_id', 'payout_transaction_id', 'correlation_id']) assert.match(migration, new RegExp(field));
  assert.match(migration, /earth_create_v2_bank_deposit/);
  assert.match(migration, /earth_post_transaction/);
  assert.match(migration, /BANK_DEPOSIT_FUNDING/);
  assert.match(migration, /SYSTEM-GLOBAL-BANK/);
  assert.match(client, /earth_create_v2_bank_deposit/);
  assert.match(client, /moneyToCents/);
  assert.doesNotMatch(client, /earth_create_bank_deposit/);
});
