import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(new URL('../db/migrations/053_tax_authority_and_statement_traceability.sql', import.meta.url), 'utf8');
const settlement = fs.readFileSync(new URL('../cloudflare/src/tax-settlement-postgres.ts', import.meta.url), 'utf8');

test('tax V2 separates assessment from payment and preserves arrears', () => {
  assert.match(migration, /ALTER TABLE tax_obligations ADD COLUMN IF NOT EXISTS nexus_type/);
  for (const field of ['taxpayer_economic_id', 'beneficiary_economic_id', 'tax_base_units', 'amount_units', 'rule_version', 'payment_transaction_id', 'due_game_day', 'correlation_id']) assert.match(fs.readFileSync(new URL('../db/migrations/001_baseline.sql', import.meta.url), 'utf8'), new RegExp(field));
  assert.match(migration, /CREATE UNIQUE INDEX IF NOT EXISTS tax_obligations_correlation_idx/);
  assert.match(settlement, /INSERT INTO tax_obligations/);
  assert.match(settlement, /status = 'ARREARS'/);
  assert.match(settlement, /earth_post_transaction/);
  assert.match(settlement, /assessedDay = day - 1/);
  assert.match(settlement, /ON CONFLICT \(correlation_id\) DO NOTHING/);
});
