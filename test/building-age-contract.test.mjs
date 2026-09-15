import test from 'node:test';
import assert from 'node:assert/strict';
import { assessBuildingAge } from '../cloudflare/src/building-age.ts';
import { readFile } from 'node:fs/promises';

test('building age is derived and capped without forced destruction', () => {
  const assessment = assessBuildingAge({ currentGameDay: 5000n, lastMajorRebuildGameDay: 1n, designLifeDays: 3650n, overdueBurdenBpsPerDay: 2n, maximumBurdenBps: 15000n });
  assert.equal(assessment.ageDays, 4999n);
  assert.equal(assessment.burdenMultiplierBps, 12698n);
  assert.equal(assessment.operable, true);
});

test('overhaul resets age while generation retrofit preserves rebuild history', async () => {
  const settlement = await readFile(new URL('../cloudflare/src/construction-settlement-postgres.ts', import.meta.url), 'utf8');
  assert.match(settlement, /project\.project_kind === 'OVERHAUL'/);
  assert.match(settlement, /GENERATION_RETROFIT/);
  assert.match(settlement, /last_major_rebuild_game_day/);
});
