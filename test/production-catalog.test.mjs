import test from 'node:test';
import assert from 'node:assert/strict';
import { MACHINE_CATALOG, productionCatalogResponse } from '../cloudflare/src/production-catalog.ts';

test('production catalog exposes food as a playable machine output', async () => {
  assert.deepEqual(MACHINE_CATALOG['food-synthesizer'], {
    output: 'food',
    credit: 4400,
    material: 75,
    capacity: 1.8,
  });

  const body = await productionCatalogResponse().json();
  const foodSector = body.sectors.find((sector) => sector.id === 'food');
  assert.equal(foodSector.machineTypes.includes('food-synthesizer'), true);
  assert.equal(foodSector.acquisition.output, 'food');
});
