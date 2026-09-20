import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const rankingsSource = fs.readFileSync('cloudflare/src/rankings-postgres.ts', 'utf8');

test('rankings use current V5 authorities only', () => {
  assert.match(rankingsSource, /economic_accounts/);
  assert.match(rankingsSource, /economic_assets/);
  assert.match(rankingsSource, /asset\.code='CREDIT'/);
  assert.match(rankingsSource, /owner_registry/);
  assert.match(rankingsSource, /building_catalog/);
  assert.match(rankingsSource, /SUM\(bc\.slot_footprint\)/);
  assert.doesNotMatch(rankingsSource, /house_residencies|territory_capacity_state|organization_memberships/);
  assert.doesNotMatch(rankingsSource, /account_balances|business_financials|business_management|business_shares|\bFROM\s+memberships\b|\bJOIN\s+memberships\b/);
  assert.doesNotMatch(rankingsSource, /housing_capacity\s+FROM\s+cities|SELECT\s+c\.housing_capacity|SELECT\s+c\.energy_capacity|SELECT\s+c\.connectivity_capacity|SELECT\s+c\.health_capacity/);
});
