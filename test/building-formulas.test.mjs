import test from 'node:test';
import assert from 'node:assert/strict';
import { deriveAllBuildingTiers, deriveBuildingTier } from '../cloudflare/src/building-formulas.ts';

const base = {
  familyCode: 'energy_plant', tier: 1, constructionCreditUnits: 100n,
  constructionMinutes: 100n, operatingCreditUnits: 10n, slotFootprint: 2n,
  inputUnits: { MATERIAL: 20n }, outputUnits: { ENERGY: 50n }, serviceCapacityUnits: 0n,
};

test('building tier formulas are deterministic, integer-only, monotonic, and capped at T5', () => {
  const tiers = deriveAllBuildingTiers(base);
  assert.equal(tiers.length, 5);
  assert.deepEqual(tiers.map((tier) => tier.tier), [1, 2, 3, 4, 5]);
  assert.deepEqual(tiers.map((tier) => tier.constructionCreditUnits), [100n, 140n, 196n, 274n, 384n]);
  assert.deepEqual(tiers.map((tier) => tier.outputUnits.ENERGY), [50n, 70n, 98n, 137n, 192n]);
  assert.equal(tiers[4].formulaVersion, 'building-formula-v1');
  assert.throws(() => deriveBuildingTier(base, 6), /between 1 and 5/i);
});
