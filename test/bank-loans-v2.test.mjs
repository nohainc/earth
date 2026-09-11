import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(new URL('../db/migrations/216_bank_loans_v2.sql', import.meta.url), 'utf8');
const balanceSheet = fs.readFileSync(new URL('../db/migrations/214_global_bank_balance_sheet.sql', import.meta.url), 'utf8');

test('V2 loan origination is generic, liquidity-funded, and supply-neutral', () => {
  assert.match(migration, /CREATE TABLE IF NOT EXISTS bank_loans/);
  for (const field of ['borrower_economic_id', 'borrower_type', 'original_principal_units', 'outstanding_principal_units', 'accrued_interest_units', 'rate_bps', 'origination_total_game_minute', 'status', 'origination_transaction_id']) assert.match(migration, new RegExp(field));
  assert.match(migration, /earth_originate_v2_bank_loan/);
  assert.match(migration, /reserve_units - deposit_liabilities_units < p_principal_units/);
  assert.match(migration, /BANK_LOAN_FUNDING/);
  assert.match(migration, /earth_post_transaction/);
  assert.match(migration, /owner_type IN \('human', 'city', 'corporation'\)/);
  assert.match(balanceSheet, /FROM bank_loans/);
});
