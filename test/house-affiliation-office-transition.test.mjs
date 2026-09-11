import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('House affiliation survives while Human authority ends at death', () => {
  const migration = read('db/migrations/302_house_affiliations_and_office_transition.sql');
  const lifecycle = read('cloudflare/src/lifecycle-postgres.ts');
  const schema = read('db/schema.sql');

  assert.match(migration, /CREATE TABLE IF NOT EXISTS house_affiliations/);
  assert.match(migration, /memberships_house_affiliation_trigger/);
  assert.match(lifecycle, /UPDATE institutions SET administrator_human_id = NULL/);
  assert.match(lifecycle, /UPDATE proposal_challenge_authorities SET status = 'ENDED_BY_DEATH'/);
  assert.match(lifecycle, /INSERT INTO memberships \(human_id, corporation_id, city_id, joined_game_day\)/);
  assert.match(schema, /house_affiliations/);
});
