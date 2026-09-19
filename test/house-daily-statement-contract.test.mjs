import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const schema = fs.readFileSync('db/baseline/01_schema.sql', 'utf8');
const functions = fs.readFileSync('db/baseline/02_functions.sql', 'utf8');
const migration = fs.readFileSync('db/migrations/016_house_daily_statements.sql', 'utf8');
const scheduler = fs.readFileSync('cloudflare/src/scheduler-postgres.ts', 'utf8');
const summary = fs.readFileSync('cloudflare/src/house-daily-summary-postgres.ts', 'utf8');

test('daily House statement has canonical balances and reconciliation components', () => {
  for (const column of ['opening_assets', 'closing_assets', 'production', 'consumption', 'market_activity', 'obligations', 'exceptions', 'net_credit_units']) {
    assert.match(schema, new RegExp(`${column} JSONB|${column} BIGINT`));
    assert.match(migration, new RegExp(column));
  }
  assert.match(functions, /earth_refresh_house_daily_statements/);
  assert.match(migration, /economic_entries/);
  assert.match(migration, /market_fills/);
  assert.match(migration, /tax_obligations/);
  assert.match(migration, /personal_life_maintenance/);
});

test('daily House statements are refreshed only after required settlement work', () => {
  assert.match(scheduler, /refreshHouseDailyStatementsInTransaction/);
  assert.match(summary, /earth_refresh_house_daily_statements/);
  assert.match(scheduler, /endOfDaySnapshots:[\s\S]*refreshHouseDailyStatementsInTransaction/);
});

test('Daily Briefing exposes the statement as a player-facing V2 contract', () => {
  assert.match(summary, /version: 2/);
  assert.match(summary, /resourceDeltas/);
  assert.match(summary, /severity: 'warning'/);
  assert.match(summary, /actionLabel: 'REVIEW FINANCE'/);
  assert.doesNotMatch(summary, /code: 'taxes_paid'/);
});

test('Daily Briefing historical facts are Day-N authoritative', () => {
  assert.match(summary, /FROM building_settlement_journals/);
  assert.match(summary, /j\.game_day = \$2/);
  assert.match(summary, /status IN \('OPERATED', 'PARTIAL'\)/);
  assert.match(summary, /FROM house_capacity_statements_v5/);
  assert.doesNotMatch(summary, /let v5Capacity/);
  assert.doesNotMatch(summary, /older read replica/);
  assert.doesNotMatch(summary, /alert\.read_at != null \|\|/);
  assert.match(summary, /formatCreditUnits\(expenses\)/);
  assert.match(summary, /formatCreditUnits\(units\(capacityRent\.assessed\)\)/);
  assert.match(summary, /producedUnits/);
  assert.match(summary, /consumedUnits/);
  assert.match(summary, /netUnits/);
  assert.doesNotMatch(summary, /produced: unitString|consumed: unitString|net: \(/);
  assert.match(summary, /bought_units/);
  assert.match(summary, /sold_units/);
  assert.match(summary, /credit_spent_units/);
  assert.match(summary, /credit_received_units/);
  assert.match(summary, /volume_units/);
  assert.match(summary, /marketActivity/);
  assert.match(summary, /cashflowBreakdown/);
  assert.match(summary, /statementMetadata/);
  assert.match(summary, /settlement_status/);
  assert.match(summary, /finalized_at/);
  assert.match(summary, /timeline/);
  assert.match(summary, /chronologicalEvents/);
  assert.match(summary, /gameMinute \?\? Number\.MAX_SAFE_INTEGER/);
  assert.match(summary, /GROUP BY t\.transaction_kind, t\.source_type/);
  assert.match(summary, /inflow_units/);
  assert.match(summary, /outflow_units/);
  assert.match(summary, /BUILDING_OPERATIONS/);
  assert.match(summary, /CONSTRUCTION/);
  assert.match(summary, /RESEARCH/);
  assert.match(summary, /CAPACITY/);
  assert.doesNotMatch(summary, /volume24h|purchasesUnits|salesUnits/);
  assert.doesNotMatch(summary, /for \(const item of resourceDeltas\.filter/);
  assert.match(summary, /FROM house_need_assessments/);
  assert.match(summary, /shortage_units/);
});
