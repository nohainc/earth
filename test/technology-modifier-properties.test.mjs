import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

const RULES = Object.freeze({
  PRODUCTION_OUTPUT: [0, 3000],
  RESOURCE_INPUT: [-3000, 3000],
  CONSTRUCTION_TIME: [-3000, 3000],
  CONSTRUCTION_RESOURCE_COST: [-3000, 3000],
  BUILDING_WEAR: [-4000, 0],
  REPAIR_EFFICIENCY: [0, 4000],
  RESEARCH_CAPACITY: [0, 2500],
  SERVICE_CAPACITY: [0, 3000],
  ENERGY_INPUT: [-3000, 3000],
});

function resolve(effects, family) {
  const [minimum, maximum] = RULES[family];
  return Math.min(maximum, Math.max(minimum, effects
    .filter((effect) => effect.family === family)
    .reduce((sum, effect) => sum + effect.bps, 0)));
}

function multiplier(bps) {
  return Math.max(0, 10_000 + bps) / 10_000;
}

function shuffle(values, random) {
  const result = [...values];
  for (let i = result.length - 1; i > 0; i -= 1) {
    const j = Math.floor(random() * (i + 1));
    [result[i], result[j]] = [result[j], result[i]];
  }
  return result;
}

test('modifier resolver uses additive capped BPS families', () => {
  const sql = read('db/migrations/257_technology_modifier_rules.sql');
  assert.match(sql, /SUM\(e\.modifier_bps\)/);
  assert.match(sql, /LEAST\(r\.maximum_bps, GREATEST\(r\.minimum_bps/);
  assert.match(sql, /stacking_mode TEXT NOT NULL DEFAULT 'ADDITIVE_BPS'/);
});

test('property: modifier stacking is invariant under technology order', () => {
  let seed = 0x12345678;
  const random = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 0x1_0000_0000);
  const families = Object.keys(RULES);

  for (let run = 0; run < 200; run += 1) {
    const effects = Array.from({ length: 1 + Math.floor(random() * 30) }, (_, index) => ({
      technology: `TECH-${index}`,
      family: families[Math.floor(random() * families.length)],
      bps: Math.floor(random() * 16_001) - 8_000,
    }));
    const expected = Object.fromEntries(families.map((family) => [family, resolve(effects, family)]));
    for (let permutation = 0; permutation < 5; permutation += 1) {
      assert.deepEqual(
        Object.fromEntries(families.map((family) => [family, resolve(shuffle(effects, random), family)])),
        expected,
      );
    }
  }
});

test('property: caps are respected and derived economic multipliers are safe', () => {
  let seed = 0xabcdef01;
  const random = () => ((seed = (seed * 1103515245 + 12345) >>> 0) / 0x1_0000_0000);
  const families = Object.keys(RULES);
  for (let run = 0; run < 300; run += 1) {
    const effects = Array.from({ length: 50 }, () => ({
      family: families[Math.floor(random() * families.length)],
      bps: Math.floor(random() * 40_001) - 20_000,
    }));
    for (const family of families) {
      const value = resolve(effects, family);
      const [minimum, maximum] = RULES[family];
      assert.ok(value >= minimum && value <= maximum);
      assert.ok(Number.isFinite(multiplier(value)));
      assert.ok(multiplier(value) > 0, `${family} must not produce a zero multiplier`);
      assert.ok(multiplier(value) <= 1 + maximum / 10_000);
    }
    assert.ok(multiplier(resolve(effects, 'RESEARCH_CAPACITY')) <= 1.25);
  }
});

test('property: equal access and rules produce an identical modifier result', () => {
  const access = ['TECH-A', 'TECH-B', 'TECH-C'];
  const effects = access.flatMap((technology, index) => [
    { technology, family: 'PRODUCTION_OUTPUT', bps: (index + 1) * 700 },
    { technology, family: 'RESOURCE_INPUT', bps: -index * 500 },
    { technology, family: 'RESEARCH_CAPACITY', bps: index * 400 },
  ]);
  const rules = JSON.stringify(RULES);
  const result = () => ({
    production: resolve(effects, 'PRODUCTION_OUTPUT'),
    input: resolve(effects, 'RESOURCE_INPUT'),
    research: resolve(effects, 'RESEARCH_CAPACITY'),
  });
  assert.equal(JSON.stringify(RULES), rules);
  assert.deepEqual(result(), result());
  assert.deepEqual(result(), {
    production: 3000,
    input: -1500,
    research: 1200,
  });
});

test('economic consumers clamp technology-derived resource and construction multipliers safely', () => {
  const building = read('cloudflare/src/building-settlement-v2.ts');
  const realEstate = read('cloudflare/src/real-estate-postgres.ts');
  assert.match(building, /inputMultiplier.*Math\.max\(0/);
  assert.match(building, /Math\.max\(0, 10000 \+ modifier\('PRODUCTION_OUTPUT'/);
  assert.match(realEstate, /constructionTimeMultiplier = Math\.max\(0/);
  assert.match(realEstate, /constructionCostMultiplier[\s\S]*?Math\.max\(0, 10000 \+ techModifier/);
});
