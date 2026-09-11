import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('House is the persistent private economic owner', () => {
  const migration = read('db/migrations/295_house_private_economic_ownership.sql');
  const schema = read('db/schema.sql');

  assert.match(migration, /owner_type IN \('human','house'/);
  assert.match(migration, /owner\.owner_type = 'house'/);
  assert.match(migration, /CASE WHEN asset\.id = 1 THEN 1 ELSE 2 END/);
  assert.match(migration, /house_private_account_map/);
  assert.match(migration, /UPDATE economic_entries/);
  assert.match(migration, /earth_private_economic_owner_id/);
  assert.match(schema, /owner_type TEXT NOT NULL CHECK \(owner_type IN \('human','house'/);
  assert.match(schema, /'house:' \|\| owner\.id \|\| ':' \|\| asset\.code/);
});

