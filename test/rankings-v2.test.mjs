import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync('cloudflare/src/read-postgres.ts', 'utf8');
const rankingsSource = source.slice(source.indexOf('export async function listRankings'), source.indexOf('export async function listHistory'));

test('rankings use current V2 authorities only', () => {
  assert.match(rankingsSource, /economic_accounts/);
  assert.match(rankingsSource, /owner_registry/);
  assert.match(rankingsSource, /house_affiliations/);
  assert.match(rankingsSource, /building_catalog_effects/);
  assert.match(rankingsSource, /bank_deposits/);
  assert.match(rankingsSource, /bank_loans/);
  assert.doesNotMatch(rankingsSource, /account_balances|business_financials|business_management|business_shares|\bFROM\s+memberships\b|\bJOIN\s+memberships\b/);
  assert.doesNotMatch(rankingsSource, /housing_capacity\s+FROM\s+cities|SELECT\s+c\.housing_capacity|SELECT\s+c\.energy_capacity|SELECT\s+c\.connectivity_capacity|SELECT\s+c\.health_capacity/);
});
