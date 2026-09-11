import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(new URL('../db/migrations/225_financial_obligations_v2.sql', import.meta.url), 'utf8');
const finance = fs.readFileSync(new URL('../cloudflare/src/finance-postgres.ts', import.meta.url), 'utf8');

test('insolvency uses projected obligations and realizable V2 assets', () => {
  assert.match(migration, /CREATE OR REPLACE VIEW financial_obligations/);
  for (const field of ['debtor_economic_id', 'creditor_economic_id', 'principal_due_units', 'interest_due_units', 'due_game_day', 'priority_class']) assert.match(migration, new RegExp(field));
  assert.match(migration, /BANK_LOAN/);
  assert.match(migration, /TAX/);
  assert.match(migration, /earth_personal_insolvency_metrics/);
  assert.match(migration, /materially_insolvent/);
  assert.match(finance, /earth_personal_insolvency_metrics/);
});
