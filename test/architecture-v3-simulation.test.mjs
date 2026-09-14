import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve('.');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

function createWorld() {
  return {
    day: 1,
    earth: { tax: 1000 },
    houses: new Map(),
    corporations: new Map(),
    territories: new Map(),
    buildings: new Map(),
    events: [],
  };
}

function foundCorporation(world, { corporationId, territoryId, houseId }) {
  assert.equal(world.corporations.has(corporationId), false);
  world.corporations.set(corporationId, { id: corporationId, tax: 500, treasury: 100_000, members: new Set([houseId]) });
  world.territories.set(territoryId, { id: territoryId, corporationId, privateSlots: 2, publicSlots: 2, usedPrivate: 0, usedPublic: 0 });
  world.houses.set(houseId, { id: houseId, corporationId, territoryId, representative: 'H-1', generation: 1 });
  world.events.push('corporation.founded', 'territory.provisioned', 'membership.joined');
}

function joinCorporation(world, houseId, corporationId) {
  const house = world.houses.get(houseId);
  const corporation = world.corporations.get(corporationId);
  assert.ok(house && corporation);
  house.corporationId = corporationId;
  house.territoryId = [...world.territories.values()].find((t) => t.corporationId === corporationId).id;
  corporation.members.add(houseId);
  world.events.push('membership.joined');
}

function expandTerritory(world, corporationId, territoryId) {
  assert.equal(world.territories.has(territoryId), false);
  world.territories.set(territoryId, { id: territoryId, corporationId, privateSlots: 4, publicSlots: 3, usedPrivate: 0, usedPublic: 0 });
  world.events.push('territory.expanded');
}

function construct(world, { buildingId, houseId, territoryId, scope }) {
  const territory = world.territories.get(territoryId);
  const slot = scope === 'PUBLIC' ? 'public' : 'private';
  const used = `used${slot[0].toUpperCase()}${slot.slice(1)}`;
  const capacity = `${slot}Slots`;
  assert.ok(territory[used] < territory[capacity]);
  territory[used] += 1;
  world.buildings.set(buildingId, { id: buildingId, houseId, territoryId, scope });
  world.events.push('building.constructed');
}

function switchCorporation(world, houseId, nextCorporationId) {
  const house = world.houses.get(houseId);
  const previous = world.corporations.get(house.corporationId);
  previous.members.delete(houseId);
  world.events.push('membership.left');
  joinCorporation(world, houseId, nextCorporationId);
  world.events.push('corporation.switched');
}

function settleDay(world) {
  world.day += 1;
  for (const corporation of world.corporations.values()) {
    const tax = corporation.members.size * corporation.tax;
    corporation.treasury += tax;
    world.earth.tax += tax;
  }
  world.events.push('taxation.settled', 'public.infrastructure.settled', 'daily.settlement.completed');
}

test('Phase 11 canonical architecture simulation completes the full lifecycle', () => {
  const world = createWorld();
  foundCorporation(world, { corporationId: 'CORP-A', territoryId: 'TERR-A', houseId: 'HOUSE-A' });
  world.houses.set('HOUSE-B', { id: 'HOUSE-B', representative: 'H-2', generation: 1 });
  joinCorporation(world, 'HOUSE-B', 'CORP-A');
  expandTerritory(world, 'CORP-A', 'TERR-B');
  construct(world, { buildingId: 'BLD-PRIVATE', houseId: 'HOUSE-A', territoryId: 'TERR-A', scope: 'PRIVATE' });
  construct(world, { buildingId: 'BLD-PUBLIC', houseId: 'HOUSE-A', territoryId: 'TERR-A', scope: 'PUBLIC' });

  const houseA = world.houses.get('HOUSE-A');
  houseA.representative = 'H-3';
  houseA.generation += 1;
  world.events.push('house.succession.completed');

  world.corporations.set('CORP-B', { id: 'CORP-B', tax: 300, treasury: 50_000, members: new Set() });
  world.territories.set('TERR-C', { id: 'TERR-C', corporationId: 'CORP-B', privateSlots: 2, publicSlots: 2, usedPrivate: 0, usedPublic: 0 });
  switchCorporation(world, 'HOUSE-B', 'CORP-B');
  settleDay(world);

  assert.equal(world.day, 2);
  assert.equal(world.houses.get('HOUSE-A').representative, 'H-3');
  assert.equal(world.houses.get('HOUSE-B').corporationId, 'CORP-B');
  assert.equal(world.buildings.get('BLD-PRIVATE').territoryId, 'TERR-A');
  assert.equal(world.buildings.get('BLD-PRIVATE').houseId, 'HOUSE-A');
  assert.equal(world.buildings.get('BLD-PUBLIC').scope, 'PUBLIC');
  assert.ok(world.corporations.get('CORP-A').treasury > 100_000);
  assert.ok(world.events.includes('daily.settlement.completed'));
});

test('canonical lifecycle modules expose all Phase 11 authorities', () => {
  const institutions = read('cloudflare/src/institutions-postgres.ts');
  const capacity = read('cloudflare/src/territory-capacity-postgres.ts');
  const fiscal = read('cloudflare/src/corporation-fiscal-postgres.ts');
  const lifecycle = read('cloudflare/src/lifecycle-postgres.ts');
  const settlement = read('cloudflare/src/territory-settlement-postgres.ts');
  const phases = read('cloudflare/src/daily-settlement-phases.ts');

  for (const token of [
    'createCorporation', 'changeCorporationMembership', 'primary_territory_id',
    'purchaseBuildingInTerritory', 'territory_id', 'spendCorporationBudget',
    'tax_rule_versions', 'house_succession_plans', 'settleTerritoryCapacityProjections',
    'settleCorporationDynamics', 'corporation_income_tax', 'territory_capacity_projections',
  ]) {
    assert.ok([institutions, capacity, fiscal, lifecycle, settlement, phases].some((source) => source.includes(token)), `missing canonical authority: ${token}`);
  }

  for (const source of [institutions, capacity, fiscal, settlement, phases]) {
    assert.doesNotMatch(source, /\bcities\b|\bcity_id\b|\bCITY-[A-Z0-9_-]+\b/i);
  }
});

test('fiscal architecture has exactly EARTH and Corporation public layers', () => {
  const schema = read('db/baseline/01_schema.sql');
  const fiscal = read('cloudflare/src/corporation-fiscal-postgres.ts');
  assert.match(schema, /scope TEXT NOT NULL CHECK \(scope IN \('EARTH','CORPORATION'\)\)/);
  assert.match(fiscal, /corporationId/);
  assert.doesNotMatch(schema, /CITY/);
  assert.doesNotMatch(fiscal, /OUC|city_id|cities/i);
});
