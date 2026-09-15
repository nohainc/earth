import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');

test('post-succession access refresh reconciles stale Human office grants', () => {
  const source = read('cloudflare/src/post-succession-access-postgres.ts');
  const phases = read('cloudflare/src/daily-settlement-phases.ts');
  const scheduler = read('cloudflare/src/scheduler-postgres.ts');
  assert.match(source, /organization_office_grants/);
  assert.match(source, /h\.status <> 'ACTIVE'/);
  assert.match(source, /effective_to_game_day/);
  assert.match(source, /RETURNING g\.id/);
  assert.match(phases, /required\('post_succession_access_refresh'/);
  assert.match(scheduler, /refreshPostSuccessionAccess/);
});
