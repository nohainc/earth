import test from 'node:test';
import assert from 'node:assert/strict';
import {
  runV5Simulation,
  V5_SCENARIOS,
  V5_RESOURCE_CODES,
} from '../simulation/v5-simulation-harness.mjs';

test('V5 Simulation Harness: 100 Houses baseline runs deterministically and healthy', () => {
  const result1 = runV5Simulation({ houses: 100, days: 90, seed: 12345, scenario: 'baseline' });
  const result2 = runV5Simulation({ houses: 100, days: 90, seed: 12345, scenario: 'baseline' });

  assert.deepEqual(result1, result2, 'Simulation must be strictly deterministic with identical seeds');
  assert.equal(result1.houses, 100);
  assert.ok(result1.survivalRate >= 0.85, `Expected high survival rate, got ${result1.survivalRate}`);
  assert.ok(result1.marketVolume.trades > 0, 'Market must have executed trades');
  assert.ok(result1.marketVolume.creditVolume > 0, 'Market must have credit volume');
  assert.ok(result1.earthRevenue > 0, 'Earth must have collected revenue');

  for (const code of V5_RESOURCE_CODES) {
    assert.ok(result1.closingPrices[code] >= 5, `${code} price must not collapse below minimum`);
    assert.ok(result1.closingPrices[code] <= 5000, `${code} price must not explode above maximum`);
    assert.ok(result1.production[code] > 0, `${code} must have non-zero production`);
    assert.ok(result1.consumption[code] > 0, `${code} must have non-zero consumption`);
  }
});

test('V5 Simulation Harness: 1,000 Houses scale benchmark executes efficiently', () => {
  const start = Date.now();
  const result = runV5Simulation({ houses: 1000, days: 90, seed: 42, scenario: 'baseline' });
  const durationMs = Date.now() - start;

  assert.equal(result.houses, 1000);
  assert.ok(result.survivalRate >= 0.80, `Expected survival rate >= 80%, got ${result.survivalRate}`);
  assert.ok(result.marketVolume.trades > 500, 'Expected extensive market activity');
  assert.ok(result.constructionFrequency.newBuildings > 0, 'Expected sustained construction activity');
  assert.ok(durationMs < 5000, `1,000 House simulation must complete within 5s, took ${durationMs}ms`);
});

test('V5 Simulation Harness: 10,000 Houses scale benchmark executes within performance budget', () => {
  const start = Date.now();
  const result = runV5Simulation({ houses: 10000, days: 30, seed: 999, scenario: 'baseline' });
  const durationMs = Date.now() - start;

  assert.equal(result.houses, 10000);
  assert.ok(result.survivalRate >= 0.80, `Expected survival rate >= 80%, got ${result.survivalRate}`);
  assert.ok(result.marketVolume.trades > 1000, 'Expected extensive market trading volume');
  assert.ok(durationMs < 5000, `10,000 House simulation must complete within 5s, took ${durationMs}ms`);
});

test('V5 Simulation Harness: All 16 economic scenarios execute and preserve non-collapse invariants', () => {
  for (const scenario of V5_SCENARIOS) {
    const result = runV5Simulation({ houses: 100, days: 60, seed: 101, scenario });
    assert.equal(result.scenario, scenario);

    // Non-collapse invariant: All resource prices stay bounded
    for (const code of V5_RESOURCE_CODES) {
      assert.ok(
        result.closingPrices[code] >= 5 && result.closingPrices[code] <= 5000,
        `Scenario ${scenario}: ${code} price ${result.closingPrices[code]} must stay within bounds [5, 5000]`,
      );
    }

    // Solvency tracking invariants
    assert.ok(result.houseSolvency.solvent >= 0 && result.houseSolvency.solvent <= 100);
    assert.ok(result.corporationSolvency.total > 0);
  }
});

test('V5 Simulation Harness: Specialization outperforms universal self-sufficiency', () => {
  const result = runV5Simulation({ houses: 500, days: 120, seed: 777, scenario: 'baseline' });
  const comparison = result.specializationComparison;

  assert.ok(
    comparison.specializationAdvantageRatio >= 1.0,
    `Specialized houses (${comparison.meanSpecializedWealth}) should outperform autarky (${comparison.meanAutarkyWealth}), ratio: ${comparison.specializationAdvantageRatio}`,
  );
});

test('V5 Simulation Harness: Corporations show economic differentiation across governance & scale scenarios', () => {
  const manyCorps = runV5Simulation({ houses: 500, days: 90, seed: 55, scenario: 'many-small-corporations' });
  const megaCorp = runV5Simulation({ houses: 500, days: 90, seed: 55, scenario: 'one-mega-corporation' });

  assert.ok(manyCorps.corporationSolvency.total >= 10, 'Many small corps scenario should have high corporation count');
  assert.equal(megaCorp.corporationSolvency.total, 1, 'Mega corp scenario should have exactly 1 corporation');
  assert.notEqual(
    manyCorps.corporationSolvency.averageTreasury,
    megaCorp.corporationSolvency.averageTreasury,
    'Corporation treasuries should be distinctly differentiated',
  );
});

test('V5 Simulation Harness: Construction and research create sustained resource demand', () => {
  const boom = runV5Simulation({ houses: 200, days: 90, seed: 88, scenario: 'construction-boom' });
  const stalled = runV5Simulation({ houses: 200, days: 90, seed: 88, scenario: 'stalled-construction' });

  assert.ok(
    boom.constructionFrequency.newBuildings > stalled.constructionFrequency.newBuildings,
    'Construction boom should yield significantly higher new buildings than stalled construction',
  );
  assert.ok(
    boom.consumption.MATERIAL > stalled.consumption.MATERIAL,
    'Construction boom should consume more Material',
  );
  assert.ok(
    boom.consumption.COMPONENTS > stalled.consumption.COMPONENTS,
    'Construction boom should consume more Components',
  );
  assert.ok(
    boom.technologyPace.researchPoints > 0,
    'Research programs should generate research points and consume Compute',
  );
});
