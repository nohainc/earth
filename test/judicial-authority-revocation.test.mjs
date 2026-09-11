import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(file, 'utf8');

test('Human-bound judicial authority is revoked on death and never inherited', () => {
  const migration = read('db/migrations/305_judicial_authority_revocation_timing.sql');
  const lifecycle = read('cloudflare/src/lifecycle-postgres.ts');
  const schema = read('db/schema.sql');

  assert.match(migration, /revoked_effective_game_day BIGINT/);
  assert.match(lifecycle, /status = 'ENDED_BY_DEATH', revoked_effective_game_day = \$2/);
  assert.match(lifecycle, /\[human\.id, day \+ 1\]/);
  assert.match(schema, /revoked_effective_game_day BIGINT/);
  assert.doesNotMatch(lifecycle, /proposal_challenge_authorities[\s\S]{0,500}newHumanId/);
});
