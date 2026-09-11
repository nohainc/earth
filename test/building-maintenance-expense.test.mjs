import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync('cloudflare/src/building-settlement-v2.ts', 'utf8');

test('maintenance is represented by the ordinary operating expense', () => {
  assert.match(source, /effectiveOperatingCost/);
  assert.match(source, /daily_operating_credits/);
  assert.match(source, /building_operating_cost/);
  assert.doesNotMatch(source, /maintenance_debt|repair_debt|building_repair|condition|wear/);
});

test('unfunded operating requirements produce no building economic effects', () => {
  assert.match(source, /const canOperate = Object\.entries\(upkeep\)/);
  assert.match(source, /if \(canOperate\) \{/);
  assert.match(source, /const opCost = canOperate \? effectiveOperatingCost : 0/);
});
