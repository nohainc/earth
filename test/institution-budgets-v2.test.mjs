import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(new URL('../db/migrations/222_institution_budgets_v2.sql', import.meta.url), 'utf8');
const finance = fs.readFileSync(new URL('../cloudflare/src/finance-postgres.ts', import.meta.url), 'utf8');

test('institution budgets authorize spending without becoming accounts', () => {
  assert.match(migration, /CREATE TABLE IF NOT EXISTS institution_budgets/);
  for (const field of ['authorized_units', 'committed_units', 'spent_units', 'rule_version', 'game_period']) assert.match(migration, new RegExp(field));
  assert.match(migration, /CREDIT remains exclusively in Economy V2 accounts/);
  assert.match(finance, /institution_budgets/);
  assert.match(finance, /spent_units/);
  assert.match(finance, /earth_post_transaction/);
});
