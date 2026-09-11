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
    'prepare_partitions', 'profile_rebuild', 'profile_settlement',
    'life_maintenance', 'basic_levy', 'building_settlement',
    'city_corporate_income_tax', 'global_bank', 'bank_health', 'budget_dividend_eligibility', 'financial_projections', 'rankings_snapshot',
    'end_of_day_snapshots',
  ];
  const indexes = requiredOrder.map((id) => phases.findIndex((phase) => phase.id === id));
  assert.ok(indexes.every((index) => index >= 0));
  assert.deepEqual(indexes, [...indexes].sort((a, b) => a - b));
  assert.ok(phases.findIndex((phase) => phase.id === 'city_corporate_income_tax') < phases.findIndex((phase) => phase.id === 'global_bank'));
  assert.ok(phases.findIndex((phase) => phase.id === 'global_bank') < phases.findIndex((phase) => phase.id === 'bank_health'));
  assert.ok(phases.findIndex((phase) => phase.id === 'bank_health') < phases.findIndex((phase) => phase.id === 'budget_dividend_eligibility'));
  assert.ok(phases.findIndex((phase) => phase.id === 'budget_dividend_eligibility') < phases.findIndex((phase) => phase.id === 'financial_states'));
});

test('scheduler uses only the resumable daily engine', () => {
  const scheduler = fs.readFileSync(path.resolve('cloudflare/src/scheduler-postgres.ts'), 'utf8');
  assert.match(scheduler, /createDailySettlementPhaseRegistry/);
  assert.doesNotMatch(scheduler, /runDailyPhase\(/);
  assert.doesNotMatch(scheduler, /resumableSettlement\s*=/);
  assert.match(scheduler, /await captureEconomyShadowOpening[\s\S]*await runResumableSettlementDay[\s\S]*await reconcileEconomyShadowDay/);
});
