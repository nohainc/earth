import test from 'node:test';
import assert from 'node:assert/strict';
import { performance } from 'node:perf_hooks';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');
const CORPORATIONS = 10_000;
const TECHNOLOGIES = 40;
const LICENSES = 100_000;
const BUILDINGS = 1_000_000;

function timed(metrics, name, work) {
  const started = performance.now();
  const result = work();
  metrics[name] = performance.now() - started;
  return result;
}

function createFixtures() {
  const access = Array.from({ length: CORPORATIONS }, (_, corporation) => [
    corporation * TECHNOLOGIES,
    corporation * TECHNOLOGIES + 1,
    corporation * TECHNOLOGIES + 2,
    corporation * TECHNOLOGIES + 3,
  ]);
  const effects = Array.from({ length: TECHNOLOGIES }, (_, technology) => ({
    technology,
    productionBps: 100 + (technology % 7) * 25,
    researchBps: technology % 5 === 0 ? 100 : 0,
  }));
  const licenses = new Uint32Array(LICENSES);
  for (let i = 0; i < licenses.length; i += 1) licenses[i] = i % CORPORATIONS;
  const buildingOwners = new Uint32Array(BUILDINGS);
  for (let i = 0; i < buildingOwners.length; i += 1) buildingOwners[i] = i % CORPORATIONS;
  return { access, effects, licenses, buildingOwners };
}

test('Technology V2 scale harness measures compact projections at target sizes', (t) => {
  const fixtures = createFixtures();
  const metrics = {};

  const cache = timed(metrics, 'modifierCacheRebuildMs', () => fixtures.access.map((technologyIds) => {
    const rows = technologyIds.map((technologyId) => fixtures.effects[technologyId % TECHNOLOGIES]);
    return {
      productionBps: Math.min(3000, rows.reduce((sum, row) => sum + row.productionBps, 0)),
      researchBps: Math.min(2500, rows.reduce((sum, row) => sum + row.researchBps, 0)),
    };
  }));

  const accessResults = timed(metrics, 'accessResolutionMs', () => {
    let granted = 0;
    for (let corporation = 0; corporation < CORPORATIONS; corporation += 1) {
      const set = new Set(fixtures.access[corporation]);
      for (let technology = 0; technology < TECHNOLOGIES; technology += 1) {
        if (set.has(corporation * TECHNOLOGIES + (technology % 4))) granted += 1;
      }
    }
    return granted;
  });

  const billed = timed(metrics, 'licenseBillingMs', () => {
    let total = 0;
    for (const corporation of fixtures.licenses) total += corporation % 2 === 0 ? 1 : 0;
    return total;
  });

  const research = timed(metrics, 'researchProgressMs', () => {
    let points = 0;
    for (let corporation = 0; corporation < CORPORATIONS; corporation += 1) {
      points += 100 + cache[corporation].researchBps;
    }
    return points;
  });

  const buildingJoin = timed(metrics, 'buildingTechnologyJoinMs', () => {
    let outputBps = 0;
    for (const owner of fixtures.buildingOwners) outputBps += cache[owner].productionBps;
    return outputBps;
  });

  assert.equal(fixtures.access.length, CORPORATIONS);
  assert.equal(fixtures.effects.length, TECHNOLOGIES);
  assert.equal(fixtures.licenses.length, LICENSES);
  assert.equal(fixtures.buildingOwners.length, BUILDINGS);
  assert.ok(accessResults > 0);
  assert.ok(billed > 0);
  assert.ok(research > 0);
  assert.ok(buildingJoin > 0);
  for (const [name, value] of Object.entries(metrics)) {
    t.diagnostic(`${name}=${value.toFixed(1)}ms`);
    assert.ok(Number.isFinite(value) && value >= 0, name);
  }
  // This is a smoke budget, not a production SLA; it catches accidental
  // quadratic work while remaining stable on ordinary development machines.
  assert.ok(metrics.buildingTechnologyJoinMs < 5_000, `building join took ${metrics.buildingTechnologyJoinMs.toFixed(1)}ms`);
});

test('Technology V2 scale paths use compact set-based projections', () => {
  const building = read('cloudflare/src/building-settlement-v2.ts');
  const scheduler = read('cloudflare/src/scheduler-postgres.ts');
  const cache = read('db/migrations/284_dirty_technology_modifier_cache.sql');
  const billing = read('db/migrations/279_set_based_ip_license_billing.sql');
  const research = read('db/migrations/289_research_scheduler_v2.sql');

  assert.match(building, /LEFT JOIN corporation_technology_modifier_cache cache/);
  assert.match(building, /cache\.game_day = \$1/);
  assert.doesNotMatch(building, /FROM technology_effects/);
  assert.match(cache, /earth_rebuild_corporation_technology_modifier_cache_bulk/);
  assert.match(cache, /INSERT INTO corporation_technology_modifier_cache/);
  assert.doesNotMatch(billing, /FOR v_contract IN/);
  assert.match(billing, /CREATE TEMP TABLE ip_license_due/);
  assert.match(research, /earth_advance_corporation_research_v2/);
  assert.match(scheduler, /earth_rebuild_corporation_technology_modifier_cache/);
});

test('Technology V2 scale fixtures preserve one cache row per corporation', () => {
  const fixtures = createFixtures();
  const cacheKeys = new Set(fixtures.access.map((_, corporation) => corporation));
  assert.equal(cacheKeys.size, CORPORATIONS);
  assert.ok(BUILDINGS / CORPORATIONS >= 100);
  assert.equal(TECHNOLOGIES, 40);
  assert.equal(LICENSES, 100_000);
  assert.equal(BUILDINGS, 1_000_000);
});
