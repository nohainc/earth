import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('Human governance offices become explicit vacancies at death', () => {
  const lifecycle = read('cloudflare/src/lifecycle-postgres.ts');
  const migration = read('db/migrations/303_governance_vacancies_on_death.sql');

  assert.match(migration, /CREATE TABLE IF NOT EXISTS governance_vacancies/);
  assert.match(lifecycle, /INSERT INTO governance_vacancies/);
  assert.match(lifecycle, /'ADMINISTRATOR'/);
  assert.match(lifecycle, /CHALLENGE_AUTHORITY:/);
  assert.match(lifecycle, /status = 'ENDED_BY_DEATH'/);
  assert.match(lifecycle, /administrator_human_id = NULL/);
  assert.doesNotMatch(lifecycle, /administrator_human_id = \$1[\s\S]{0,200}newHumanId/);
});
