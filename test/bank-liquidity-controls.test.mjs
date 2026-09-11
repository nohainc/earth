import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(new URL('../db/migrations/218_bank_liquidity_controls.sql', import.meta.url), 'utf8');

test('Global Bank rules are versioned and constrain loan admission', () => {
  assert.match(migration, /CREATE TABLE IF NOT EXISTS global_bank_rules/);
  for (const field of [
    'minimum_liquidity_ratio',
    'minimum_capital_ratio',
    'maximum_single_borrower_exposure_units',
    'maximum_total_lending_ratio',
    'deposit_rate_bps',
    'loan_rate_bps',
    'grace_period_days',
    'default_threshold_days',
    'effective_from_game_day',
    'effective_to_game_day',
  ]) assert.match(migration, new RegExp(field));
  assert.match(migration, /earth_validate_bank_loan_admission/);
  assert.match(migration, /earth_validate_bank_rate_snapshot/);
  assert.match(migration, /Borrower is not eligible/);
  assert.match(migration, /maximum_single_borrower_exposure_units/);
  assert.match(migration, /maximum_total_lending_ratio/);
  assert.match(migration, /minimum_liquidity_ratio/);
  assert.match(migration, /minimum_capital_ratio/);
  assert.match(migration, /earth_originate_v2_bank_loan/);
  assert.match(migration, /PERFORM earth_validate_bank_loan_admission/);
  assert.match(migration, /chr\(10\)/);
});
