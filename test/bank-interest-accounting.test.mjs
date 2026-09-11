import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(new URL('../db/migrations/217_bank_interest_accounting.sql', import.meta.url), 'utf8');

test('bank interest accrual is distinct from CREDIT settlement', () => {
  assert.match(migration, /earth_accrue_bank_interest/);
  assert.match(migration, /accrued_interest_units = accrued_interest_units/);
  assert.match(migration, /last_interest_game_day/);
  assert.match(migration, /earth_pay_v2_bank_loan/);
  assert.match(migration, /interest_paid := LEAST/);
  assert.match(migration, /BANK_LOAN_PAYMENT/);
  assert.match(migration, /earth_withdraw_v2_bank_deposit/);
  assert.match(migration, /BANK_DEPOSIT_PAYOUT/);
  assert.match(migration, /earth_post_transaction/);
  assert.match(migration, /bank_loan_payments/);
});
