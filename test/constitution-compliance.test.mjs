import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(file, 'utf8');

test('constitutional compliance guard: Economy V2 is the authority in V2 mutation paths', () => {
  const v2MutationPaths = [
    'cloudflare/src/market-postgres.ts',
    'cloudflare/src/building-settlement-v2.ts',
    'cloudflare/src/institution-spending.ts',
    'cloudflare/src/proposal-finance-actions.ts',
  ];
  for (const file of v2MutationPaths) {
    const source = read(file);
    assert.doesNotMatch(source, /account_balances|resource_balances|ledger_entries|resource_ledger_entries/i, `${file} must not mutate legacy ledgers`);
  }
  const building = read('cloudflare/src/building-settlement-v2.ts');
  assert.doesNotMatch(building, /output_credits|resource_output_type\s*===?\s*['"]credits['"]/i);
  assert.match(building, /building_output_issuance/);
  assert.match(building, /building_output/);
});

test('constitutional compliance guard: economic periods and tax changes are daily/prospective', () => {
  const dailyPhaseSource = read('cloudflare/src/daily-settlement-phases.ts');
  const taxExecutor = read('cloudflare/src/proposal-finance-actions.ts');
  assert.doesNotMatch(dailyPhaseSource, /monthly|annual|per_month|month_income/i);
  assert.match(taxExecutor, /effectiveDay <= gameDay/);
  assert.match(taxExecutor, /future game day/);
  assert.match(read('db/baseline/01_schema.sql'), /tax_rule_versions/);
  assert.match(read('cloudflare/src/proposal-finance-actions.ts'), /authorization_proposal_id|STALE_CONFLICT/);
});

test('constitutional compliance guard: House continuity keeps economic ownership at succession', () => {
  const lifecycle = read('cloudflare/src/lifecycle-postgres.ts');
  const start = lifecycle.indexOf('export async function processHouseMortality');
  const end = lifecycle.indexOf('export async function activatePendingHouseSuccessors');
  assert.ok(start >= 0 && end > start, 'Modern House mortality handler must exist');
  const houseMortality = lifecycle.slice(start, end);
  assert.match(houseMortality, /owner_economic_id|house_affiliations/);
  assert.match(houseMortality, /current_human_id/);
  assert.doesNotMatch(houseMortality, /account_balances|resource_balances/);
  assert.match(read('docs/CONSTITUTION.md'), /House property, contracts, debts, affiliations/);
});
