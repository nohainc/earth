import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

test('institution budget cutover retires the legacy budget table', () => {
  const migration = read('db/migrations/316_remove_legacy_budgets.sql');
  const schema = read('db/schema.sql');

  assert.match(migration, /INSERT INTO institution_budget_lines/);
  assert.match(migration, /DROP TABLE budgets/);
  assert.match(schema, /CREATE TABLE IF NOT EXISTS institution_budget_lines/);
  assert.doesNotMatch(schema, /CREATE TABLE IF NOT EXISTS budgets/);
});

test('institution spending has one generic Economy V2 entry point', () => {
  const spending = read('cloudflare/src/institution-spending.ts');
  const institutions = read('cloudflare/src/institutions-postgres.ts');
  const grants = read('cloudflare/src/institution-grants.ts');

  assert.match(spending, /export async function spendInstitutionBudget/);
  assert.match(institutions, /spendBudget\(tx/);
  assert.match(grants, /spendBudget\(tx/);
  assert.doesNotMatch(institutions, /UPDATE\s+(cities|corporations)\s+SET\s+treasury/i);
  assert.doesNotMatch(spending, /account_balances|resource_balances|ledger_entries/i);
});

test('institution cash remains Economy V2 while scalar treasury is projection-only', () => {
  const treasuryMigration = read('db/migrations/212_institution_treasury_v2_authority.sql');
  const authorityMigration = read('db/migrations/315_economy_v2_institution_treasury_authority.sql');
  const spending = read('cloudflare/src/institution-spending.ts');

  assert.match(treasuryMigration, /Deprecated compatibility projection/);
  assert.match(authorityMigration, /scalar.*Economy V2|Economy V2.*scalar/i);
  assert.match(spending, /FROM economic_accounts/);
  assert.match(spending, /earth_post_transaction/);
});

test('city capacity is a rebuildable projection and fiscal failure uses receivership', () => {
  const capacity = read('db/migrations/329_city_service_capacity_projection.sql');
  const receivership = read('db/migrations/228_city_fiscal_insolvency_v2.sql');
  const scheduler = read('cloudflare/src/scheduler-postgres.ts');

  assert.match(capacity, /CREATE TABLE city_service_capacity_daily/);
  assert.match(capacity, /earth_refresh_city_service_capacity_daily/);
  assert.doesNotMatch(capacity, /UPDATE cities\s+SET\s+(housing_capacity|energy_capacity|connectivity_capacity|health_capacity)/i);
  assert.match(receivership, /earth_open_city_receivership/);
  assert.match(receivership, /receivership/);
  assert.match(scheduler, /city_service_capacity_daily/);
});

test('legacy budget and direct treasury paths are absent from current institutional modules', () => {
  const source = [
    read('cloudflare/src/engines/institutions-engine.ts'),
    read('cloudflare/src/finance-postgres.ts'),
    read('cloudflare/src/institutions-postgres.ts'),
    read('cloudflare/src/civic-dividend-engine.ts'),
    read('cloudflare/src/institution-budget-api.ts'),
  ].join('\n');

  assert.doesNotMatch(source, /FROM budgets|UPDATE budgets|INTO budgets/i);
  assert.doesNotMatch(source, /UPDATE\s+(cities|corporations)\s+SET\s+treasury/i);
  assert.doesNotMatch(source, /continuous-budget-engine/i);
  assert.match(source, /institution_budget_lines/);
});
