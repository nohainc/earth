import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(file, 'utf8');

test('institution treasury authority uses Economy V2 and removes scalar columns', () => {
  const migration = read('db/migrations/315_economy_v2_institution_treasury_authority.sql');
  const schema = read('db/schema.sql');
  const source = [
    read('cloudflare/src/institutions-postgres.ts'),
    read('cloudflare/src/read-postgres.ts'),
    read('cloudflare/src/world-postgres.ts'),
    read('cloudflare/src/engines/rankings-engine.ts'),
    read('cloudflare/src/scheduler-postgres.ts'),
    read('cloudflare/src/social-directory-postgres.ts'),
  ].join('\n');

  assert.match(migration, /scalar_treasury <> economic_treasury/);
  assert.match(migration, /DROP COLUMN IF EXISTS treasury/);
  assert.match(migration, /account_type = 3/);
  assert.doesNotMatch(schema, /treasury NUMERIC\(20,2\)/);
  assert.doesNotMatch(source, /(?:cities|corporations)\.treasury/);
  assert.match(source, /economic_accounts/);
  assert.match(source, /is_default_settlement/);
});
