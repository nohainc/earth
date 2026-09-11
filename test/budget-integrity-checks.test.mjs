import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(new URL('../db/migrations/338_budget_integrity_checks.sql', import.meta.url), 'utf8');
const schema = fs.readFileSync(new URL('../db/schema.sql', import.meta.url), 'utf8');

test('budget integrity extends the canonical Economy V2 integrity report', () => {
  for (const source of [migration, schema]) {
    assert.match(source, /earth_integrity_report/);
    for (const check of ['budget_authority_exceeded', 'negative_budget_units', 'negative_commitment_remaining', 'spending_event_without_economic_transaction', 'institution_transaction_without_financial_event', 'grant_received_counted_as_spending', 'reserve_transfer_unbalanced']) assert.match(source, new RegExp(check));
  }
});

test('receivership blocks new discretionary commitments at the database boundary', () => {
  assert.match(migration, /earth_reject_receivership_discretionary_commitment/);
  assert.match(migration, /BEFORE INSERT ON institution_budget_commitments/);
  assert.match(migration, /receivership/);
});
