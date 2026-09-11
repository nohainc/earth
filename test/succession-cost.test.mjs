import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('succession cost is optional, governance-versioned, liquid-only, and Economy V2-posted', () => {
  const lifecycle = fs.readFileSync('cloudflare/src/lifecycle-postgres.ts', 'utf8');
  const mortality = lifecycle;

  assert.match(mortality, /category = 'succession'/);
  assert.match(mortality, /successionCostUnits/);
  assert.match(mortality, /successionCostBps/);
  assert.match(mortality, /requested < balance \? requested : balance/);
  assert.match(mortality, /SUCCESSION_COST/);
  assert.match(mortality, /succession-cost:\$\{houseId\}:\$\{day\}/);
  assert.match(mortality, /successionCostRuleVersion/);
});
