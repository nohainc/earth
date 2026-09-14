import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { RESOURCE_FLOW_DEFINITIONS } from '../simulation/resource-flow-definitions.mjs';
import { runResourceEconomySimulation } from '../simulation/resource-economy-simulator.mjs';

test('resource simulator uses the normalized T1 resource graph', () => {
  const migration = fs.readFileSync('db/migrations/007_core_resource_graph_t1.sql', 'utf8');
  for (const code of Object.keys(RESOURCE_FLOW_DEFINITIONS)) assert.match(migration, new RegExp(code));
  assert.deepEqual(Object.keys(RESOURCE_FLOW_DEFINITIONS).sort(), ['COMPONENT-FAB-T1', 'COMPUTE-FAB-T1', 'ENERGY-PLANT-T1', 'FOOD-FARM-T1', 'MATERIAL-FAB-T1'].sort());
});

test('resource simulator reports the Phase 9 metrics deterministically', () => {
  const options = { houses: 100, days: 365, seed: 42, specialization: 'mixed', scenario: 'baseline' };
  const first = runResourceEconomySimulation(options);
  const second = runResourceEconomySimulation(options);
  assert.deepEqual(first, second);
  for (const metric of ['production', 'consumption', 'inventoryGrowth', 'shortage', 'averagePrices', 'averageUtilization']) assert.ok(metric in first);
  assert.equal(first.houses, 100);
  assert.ok(first.constructionStarted >= 0);
  assert.ok(first.survivingHouses <= 100);
});

test('stress scenarios change measured outcomes', () => {
  const normal = runResourceEconomySimulation({ houses: 1000, days: 365, scenario: 'baseline' });
  const energy = runResourceEconomySimulation({ houses: 1000, days: 365, scenario: 'energy-shortage' });
  const retrofit = runResourceEconomySimulation({ houses: 1000, days: 3650, scenario: 'generation-retrofit-boom' });
  assert.ok(energy.shortage.ENERGY >= normal.shortage.ENERGY);
  assert.ok(retrofit.constructionStarted >= normal.constructionStarted);
});
