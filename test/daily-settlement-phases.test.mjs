import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

test('daily settlement has one ordered canonical phase registry', () => {
  const source = fs.readFileSync(path.resolve('cloudflare/src/daily-settlement-phases.ts'), 'utf8');
  const phases = [...source.matchAll(/id: '([^']+)', order: (\d+), shardMode: '([^']+)'/g)]
    .map((match) => ({ id: match[1], order: Number(match[2]), shardMode: match[3] }));

  assert.ok(phases.length >= 16);
  assert.deepEqual(phases, [...phases].sort((a, b) => a.order - b.order));
  assert.equal(phases.find((phase) => phase.id === 'profile_rebuild')?.shardMode, 'owner-shards');

  const requiredOrder = [
    'succession_activation', 'prepare_partitions', 'profile_rebuild', 'profile_settlement',
    'ip_license_billing', 'life_maintenance', 'building_settlement', 'basic_levy',
    'corporation_income_tax', 'global_bank', 'bank_health',
    'territory_capacity_projections', 'corporation_dynamics',
    'budget_dividend_eligibility', 'financial_states', 'lifecycle', 'post_succession_access_refresh',
    'financial_projections', 'rankings_snapshot', 'end_of_day_snapshots',
  ];
  const indexes = requiredOrder.map((id) => phases.findIndex((phase) => phase.id === id));
  assert.ok(indexes.every((index) => index >= 0));
  assert.deepEqual(indexes, [...indexes].sort((a, b) => a - b));
  assert.ok(phases.findIndex((phase) => phase.id === 'corporation_income_tax') < phases.findIndex((phase) => phase.id === 'global_bank'));
  assert.ok(!source.match(/city_service_projections|city_dynamics|city_corporate_income_tax/));
  assert.ok(phases.findIndex((phase) => phase.id === 'global_bank') < phases.findIndex((phase) => phase.id === 'bank_health'));
  assert.ok(phases.findIndex((phase) => phase.id === 'bank_health') < phases.findIndex((phase) => phase.id === 'budget_dividend_eligibility'));
  assert.ok(phases.findIndex((phase) => phase.id === 'budget_dividend_eligibility') < phases.findIndex((phase) => phase.id === 'financial_states'));
  assert.ok(phases.findIndex((phase) => phase.id === 'financial_states') < phases.findIndex((phase) => phase.id === 'lifecycle'));
  assert.ok(phases.findIndex((phase) => phase.id === 'life_maintenance') < phases.findIndex((phase) => phase.id === 'building_settlement'));
  assert.ok(phases.findIndex((phase) => phase.id === 'life_maintenance') < phases.findIndex((phase) => phase.id === 'building_settlement'));
  assert.ok(phases.findIndex((phase) => phase.id === 'lifecycle') < phases.findIndex((phase) => phase.id === 'end_of_day_snapshots'));
  assert.ok(phases.findIndex((phase) => phase.id === 'lifecycle') < phases.findIndex((phase) => phase.id === 'post_succession_access_refresh'));
});

test('scheduler uses only the resumable daily engine', () => {
  const scheduler = fs.readFileSync(path.resolve('cloudflare/src/scheduler-postgres.ts'), 'utf8');
  assert.match(scheduler, /createDailySettlementPhaseRegistry/);
  assert.match(scheduler, /for \(const phase of settlementPhases\)/);
  assert.match(scheduler, /territoryCapacityProjections/);
  assert.match(scheduler, /corporationDynamics/);
});

test('daily automation has no City settlement dependencies', () => {
  const automation = fs.readFileSync(path.resolve('cloudflare/src/daily-automation.ts'), 'utf8');
  assert.doesNotMatch(automation, /city_service|city_dynamics|city_corporate|city_id|cities|OUC|CITY/);
});
