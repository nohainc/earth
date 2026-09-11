import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('restricted grants cap recipient budget spending without creating accounts', () => {
  const migration = read('db/migrations/323_grant_restrictions.sql');
  const spending = read('cloudflare/src/institution-spending.ts');
  const grants = read('cloudflare/src/institution-grants.ts');
  assert.match(migration, /CREATE TABLE grant_restrictions/);
  assert.match(migration, /category_id BIGINT NOT NULL REFERENCES budget_categories/);
  assert.match(spending, /restrictionId/);
  assert.match(spending, /Spending exceeds restricted grant authority/);
  assert.match(spending, /UPDATE grant_restrictions SET remaining_units/);
  assert.match(grants, /restrictInstitutionGrant/);
  assert.doesNotMatch(migration, /economic_accounts/);
});
