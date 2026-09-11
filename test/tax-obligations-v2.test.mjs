import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(new URL('../db/migrations/220_tax_obligations_v2.sql', import.meta.url), 'utf8');

test('tax V2 separates assessment from payment and preserves arrears', () => {
  assert.match(migration, /CREATE TABLE IF NOT EXISTS tax_obligations/);
  for (const field of ['taxpayer_economic_id', 'beneficiary_economic_id', 'tax_base_units', 'rate_bps', 'amount_units', 'rule_version', 'payment_transaction_id']) assert.match(migration, new RegExp(field));
  assert.match(migration, /status IN \('DUE', 'PARTIAL', 'ARREARS'\)/);
  assert.match(migration, /earth_settle_v2_tax_obligations/);
  assert.match(migration, /correlation_id TEXT NOT NULL UNIQUE/);
  assert.match(migration, /earth_post_settlement_batch/);
  assert.match(migration, /status = CASE WHEN d\.paid_units >= d\.amount_units THEN 'PAID'/);
  assert.match(migration, /ELSE 'ARREARS' END/);
  assert.match(migration, /tax_type IN \('basic_levy', 'personal_income', 'corporate_income', 'market_transaction', 'property', 'building'\)/);
});
