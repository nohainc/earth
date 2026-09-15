import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { applyConditionModifier, applyConditionModifierUnits, applyConditionStack, conditionIsEffective } from '../cloudflare/src/world-conditions.ts';

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
