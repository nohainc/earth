import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('institution grants are explicit transfers with separate recipient spending', () => {
  const schema = read('db/schema.sql');
  const migration = read('db/migrations/322_institution_grants.sql');
  const source = read('cloudflare/src/institution-grants.ts');
  assert.match(schema, /CREATE TABLE IF NOT EXISTS institution_grants/);
  assert.match(migration, /grantor_institution_id/);
  assert.match(migration, /recipient_institution_id/);
  assert.match(migration, /status TEXT NOT NULL DEFAULT 'APPROVED'/);
  assert.match(source, /approveInstitutionGrant/);
  assert.match(source, /earth_create_budget_commitment/);
  assert.match(source, /payInstitutionGrant/);
  assert.match(source, /spendBudget/);
  assert.match(source, /INSTITUTION_GRANT/);
  assert.match(source, /status = \\'PAID\\'/);
});
