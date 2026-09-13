import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');

test('Game Event Journal V2 is the canonical durable history model', () => {
  const migration = read('db/migrations/003_game_events_v2.sql');
  const helper = read('cloudflare/src/game-events-postgres.ts');
  const reader = read('cloudflare/src/read-postgres.ts');
  const routes = read('cloudflare/src/read-model-routes.ts');
  const registry = read('cloudflare/src/api-registry.ts');

  assert.match(migration, /CREATE TABLE game_events/);
  assert.match(migration, /details TEXT NOT NULL/);
  assert.match(migration, /correlation_id TEXT NULL UNIQUE/);
  assert.match(migration, /game_events_category_day_idx/);
  assert.match(helper, /toNanoMarkup/);
  assert.match(helper, /INSERT INTO game_events/);
  assert.match(helper, /ON CONFLICT DO NOTHING/);
  assert.match(helper, /HOUSE_\$\{input\.action\}_\$\{input\.institutionType\}/);
  assert.match(reader, /FROM game_events/);
  assert.match(reader, /category = \$2/);
  assert.match(routes, /url\.pathname === '\/api\/events'/);
  assert.match(routes, /Unknown event category/);
  assert.match(registry, /GET', path: '\/api\/events'/);

  for (const retired of ['world_events', 'ownership_events', 'membership_events']) {
    assert.doesNotMatch(helper, new RegExp(retired));
    assert.doesNotMatch(reader, new RegExp(retired));
    assert.doesNotMatch(routes, new RegExp(retired));
  }
});

test('Nano Markup remains the event detail representation', () => {
  const migration = read('db/migrations/003_game_events_v2.sql');
  const helper = read('cloudflare/src/game-events-postgres.ts');
  assert.doesNotMatch(migration, /details\s+JSONB/i);
  assert.match(helper, /typeof input\.details === 'string'/);
  assert.match(helper, /toNanoMarkup\(input\.details/);
});
