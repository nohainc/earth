import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');

test('institution financial snapshots are a bounded, idempotent V4 projection', () => {
  const migration = read('db/migrations/057_institution_financial_snapshots.sql');
  const settlement = read('cloudflare/src/institution-financial-settlement-postgres.ts');
  const phases = read('cloudflare/src/daily-settlement-phases.ts');
  const scheduler = read('cloudflare/src/scheduler-postgres.ts');

  assert.match(migration, /institution_financial_snapshots/);
  assert.match(migration, /PRIMARY KEY \(institution_id, game_day\)/);
  assert.match(migration, /CHECK \(budget_authorized_units >= budget_committed_units \+ budget_spent_units\)/);
  assert.match(settlement, /economic_transactions/);
  assert.match(settlement, /ON CONFLICT \(institution_id, game_day\) DO UPDATE/);
  assert.match(settlement, /institution_financial_snapshots/);
  assert.match(phases, /required\('financial_projections'/);
  assert.match(scheduler, /refreshInstitutionFinancialSnapshots/);
});
