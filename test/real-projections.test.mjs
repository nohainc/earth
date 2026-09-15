import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');

test('service status uses authoritative projections and retired production events stay absent', () => {
  const index = read('cloudflare/src/index.ts');
  const activity = read('cloudflare/src/read-model-routes.ts');
  const world = read('cloudflare/src/world-postgres.ts');
  assert.match(index, /getServiceStatusPostgres/);
  assert.doesNotMatch(index, /productionEventsFromPostgres|\/api\/production\/events|events: \[\]/);
  assert.doesNotMatch(index, /ouc-independent-minimum|housing: 0\.75/);
  assert.doesNotMatch(activity, /batch: world\.rows\[0\]\?\.market_batch_seconds \?\? 498/);
  assert.doesNotMatch(world, /day: worldRow\.game_day \?\? 184|batch: worldRow\.market_batch_seconds \?\? 498/);
});
