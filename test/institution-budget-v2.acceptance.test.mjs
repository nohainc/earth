import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

test('institutional cash, authorization, commitments and payments are separate', () => {
  const spending = read('cloudflare/src/institution-spending.ts');
  const authorization = read('cloudflare/src/budget-authorization.ts');
  const commitments = read('db/migrations/320_budget_commitments.sql');
  const schema = read('db/schema.sql');

  assert.match(spending, /FROM economic_accounts/);
  assert.match(spending, /earth_post_transaction/);
  assert.match(spending, /authorized_units.*committed_units.*spent_units/);
  assert.doesNotMatch(authorization, /earth_post_transaction/);
  assert.match(commitments, /FOR UPDATE/);
  assert.match(schema, /institution_budget_lines/);
});

test('institutional transfers and events preserve the treasury boundary', () => {
  const grants = read('cloudflare/src/institution-grants.ts');
  const events = read('db/migrations/336_institution_financial_events.sql');
  const treasury = read('db/migrations/315_economy_v2_institution_treasury_authority.sql');

  assert.match(grants, /GRANT_SENT/);
  assert.match(grants, /GRANT_RECEIVED/);
  assert.match(grants, /spendBudget\(tx/);
  assert.match(events, /economic_transaction_id/);
  assert.match(treasury, /DROP COLUMN IF EXISTS treasury/);
});

test('budget authority, roles, affiliations and institutional states are V2 models', () => {
  const authorization = read('db/migrations/332_institution_action_authorization.sql');
  const affiliation = read('db/migrations/333_house_affiliations_authority.sql');
  const population = read('db/migrations/334_house_population_projections.sql');
  const receivership = read('db/migrations/228_city_fiscal_insolvency_v2.sql');
  const corporate = read('cloudflare/src/scheduler-postgres.ts');

  assert.match(authorization, /earth_can_perform_institution_action/);
  assert.match(authorization, /DECLARE_DIVIDEND/);
  assert.match(affiliation, /house_affiliations/);
  assert.match(population, /city_population_summary/);
  assert.match(population, /corporation_membership_summary/);
  assert.match(receivership, /earth_open_city_receivership/);
  assert.match(corporate, /target === 'liquidation'/);
});

test('services and projections remain derived rather than budget-created', () => {
  const capacity = read('db/migrations/329_city_service_capacity_projection.sql');
  const projections = read('db/migrations/337_institution_financial_projections.sql');
  const scheduler = read('cloudflare/src/scheduler-postgres.ts');

  assert.match(capacity, /building_settlement_journals/);
  assert.match(capacity, /earth_refresh_city_service_capacity_daily/);
  assert.doesNotMatch(capacity, /UPDATE cities\s+SET\s+(housing_capacity|energy_capacity|connectivity_capacity|health_capacity)/i);
  assert.match(projections, /institution_financial_projections/);
  assert.match(projections, /budget_authorized_units/);
  assert.match(projections, /budget_spent_units/);
  assert.match(scheduler, /earth_refresh_city_service_capacity_daily/);
});

test('legacy institutional budget and treasury mutation paths are absent', () => {
  const source = [
    read('cloudflare/src/institution-spending.ts'),
    read('cloudflare/src/institution-budget-api.ts'),
    read('cloudflare/src/institution-grants.ts'),
    read('cloudflare/src/institutions-postgres.ts'),
    read('cloudflare/src/finance-postgres.ts'),
  ].join('\n');

  assert.doesNotMatch(source, /FROM budgets|UPDATE budgets|INTO budgets|continuous-budget-engine/i);
  assert.doesNotMatch(source, /UPDATE\s+(cities|corporations)\s+SET\s+treasury/i);
  assert.match(source, /institution_budget_lines/);
  assert.match(source, /economic_accounts/);
});
