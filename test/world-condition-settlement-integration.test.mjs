import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('world condition modifiers flow into deterministic service demand and capacity', () => {
  const settlement = fs.readFileSync('cloudflare/src/service-settlement-postgres.ts', 'utf8');
  const feed = fs.readFileSync('cloudflare/src/world-conditions-postgres.ts', 'utf8');
  assert.match(settlement, /FROM world_conditions/);
  assert.match(settlement, /DEMAND_MULTIPLIER/);
  assert.match(settlement, /CAPACITY_MULTIPLIER/);
  assert.match(settlement, /organization_economies/);
  assert.match(settlement, /scope_type === 'ORGANIZATION'/);
  assert.match(settlement, /applyConditionStack/);
  const construction = fs.readFileSync('cloudflare/src/territory-capacity-postgres.ts', 'utf8');
  assert.match(construction, /CONSTRUCTION_INDEX/);
  assert.match(construction, /effectiveConstructionMinutes/);
  const buildings = fs.readFileSync('cloudflare/src/building-settlement-v2.ts', 'utf8');
  assert.match(buildings, /SUPPLY_MULTIPLIER/);
  assert.match(buildings, /DEMAND_MULTIPLIER/);
  assert.match(buildings, /adjustedInputUnits/);
  assert.match(feed, /effective_to_game_day/);
});
