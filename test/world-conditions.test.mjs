import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { applyConditionModifier, applyConditionModifierUnits, applyConditionStack, conditionIsEffective, WORLD_CONDITION_EFFECT_REGISTRY, WORLD_CONDITION_EFFECTS } from '../cloudflare/src/world-conditions.ts';

test('world conditions are effective-dated and transparent', () => {
  assert.equal(conditionIsEffective({ effectiveFromGameDay: 10, effectiveToGameDay: 20 }, 9), false);
  assert.equal(conditionIsEffective({ effectiveFromGameDay: 10, effectiveToGameDay: 20 }, 10), true);
  assert.equal(conditionIsEffective({ effectiveFromGameDay: 10, effectiveToGameDay: null }, 1000), true);
  assert.ok(Math.abs(applyConditionModifier(100, 250) - 102.5) < 1e-9);
  assert.equal(applyConditionModifier(100, -5000), 50);
  assert.equal(applyConditionModifierUnits(100n, 250), 102n);
  assert.equal(applyConditionStack(100n, [1000, -5000]), 55n);
});

test('labor-index conditions participate in construction duration without a second cost authority', () => {
  const source = fs.readFileSync(new URL('../cloudflare/src/territory-capacity-postgres.ts', import.meta.url), 'utf8');
  assert.match(source, /effect_type IN \('CONSTRUCTION_INDEX', 'LABOR_INDEX'\)/);
  assert.match(source, /conditionModifiers/);
  assert.match(source, /effectiveConstructionMinutes/);
});

test('every advertised condition effect has one authoritative consumer and fixed-point stacking', () => {
  assert.deepEqual(new Set(WORLD_CONDITION_EFFECTS), new Set(Object.keys(WORLD_CONDITION_EFFECT_REGISTRY)));
  for (const [effect, metadata] of Object.entries(WORLD_CONDITION_EFFECT_REGISTRY)) {
    assert.notEqual(metadata.consumer, '');
    assert.equal(metadata.stacking, 'SEQUENTIAL_BPS', effect);
    assert.ok(metadata.unit === 'RESOURCE_UNITS' || metadata.unit === 'GAME_MINUTES');
  }
  assert.equal(WORLD_CONDITION_EFFECT_REGISTRY.LABOR_INDEX.consumer, 'territory-capacity.construction-quote');
  assert.equal(WORLD_CONDITION_EFFECT_REGISTRY.CONSTRUCTION_INDEX.consumer, 'territory-capacity.construction-quote');
});

test('condition identity and effect records are normalized and provenance-versioned', () => {
  const migration = fs.readFileSync('db/migrations/174_normalize_world_condition_effects.sql', 'utf8');
  const readModel = fs.readFileSync('cloudflare/src/world-conditions-postgres.ts', 'utf8');
  assert.match(migration, /CREATE TABLE IF NOT EXISTS world_condition_effects/);
  assert.match(migration, /definition_version/);
  assert.match(migration, /INSERT INTO world_condition_effects/);
  assert.match(migration, /DROP COLUMN IF EXISTS effect_type/);
  assert.match(readModel, /jsonb_agg/);
  assert.match(readModel, /definitionVersion/);
  assert.match(readModel, /source: \{ type: String\(row\.source_type\), id: String\(row\.source_id\) \}/);
});
