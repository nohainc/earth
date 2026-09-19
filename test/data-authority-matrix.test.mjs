import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const matrix = fs.readFileSync('docs/DATA_AUTHORITY_MATRIX.md', 'utf8');

test('data authority matrix covers the economic sources of truth', () => {
  for (const authority of [
    'building_catalog', 'building_economic_rule_versions',
    'corporation_building_unlocks', 'technology_catalog', 'technology_effects',
    'tax_rule_versions', 'economic_reference_prices', 'institution_budget_lines',
    'institution_budget_commitments', 'v5_house_settlement_profiles',
    'v5_corporation_settlement_profiles', 'corporation_capacity_state_v5',
    'resolved_constitution_snapshots_v5', 'progressive_policy_brackets',
    'economic_accounts', 'completed Spot Market batches/fills',
  ]) assert.match(matrix, new RegExp(authority.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  assert.match(matrix, /one authoritative source/);
  assert.match(matrix, /compatibility fallback only/);
  assert.match(matrix, /must never be written back as a new source value/);
  assert.doesNotMatch(matrix, /\bcity_service_capacity_daily\b/);
});

test('balance analysis is explicitly isolated from live market prices', () => {
  assert.match(matrix, /Balance analysis uses stable reference prices/);
  assert.match(matrix, /never substitutes current[\s\S]*Spot Market prices/);
  assert.match(matrix, /market_prices.*transitional read projection/i);
});
