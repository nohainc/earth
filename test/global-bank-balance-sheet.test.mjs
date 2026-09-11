import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(new URL('../db/migrations/214_global_bank_balance_sheet.sql', import.meta.url), 'utf8');
const schema = fs.readFileSync(new URL('../db/schema.sql', import.meta.url), 'utf8');

test('Global Bank balance sheet is a derived V2 projection', () => {
  assert.match(migration, /CREATE TABLE IF NOT EXISTS global_bank_balance_sheet/);
  for (const field of ['reserve_units', 'performing_loans_units', 'impaired_loans_units', 'interest_receivable_units', 'deposit_principal_units', 'deposit_interest_payable_units', 'withdrawals_payable_units', 'assets_units', 'liabilities_units', 'equity_units', 'liquidity_ratio', 'capital_ratio', 'status']) {
    assert.match(migration, new RegExp(field));
  }
  assert.match(migration, /earth_refresh_global_bank_balance_sheet/);
  assert.match(migration, /SYSTEM-GLOBAL-BANK/);
  assert.match(migration, /economic_accounts/);
  assert.match(migration, /assets - liabilities/);
  assert.match(migration, /reserve_units::NUMERIC \/ liabilities/);
  assert.doesNotMatch(migration, /UPDATE\s+global_bank_balance_sheet\s+SET\s+equity/);
  assert.match(schema, /CREATE TABLE IF NOT EXISTS global_bank_balance_sheet/);
});
