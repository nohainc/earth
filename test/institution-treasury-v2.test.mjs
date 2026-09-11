import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(new URL('../db/migrations/212_institution_treasury_v2_authority.sql', import.meta.url), 'utf8');
const institutions = fs.readFileSync(new URL('../cloudflare/src/institutions-postgres.ts', import.meta.url), 'utf8');
const finance = fs.readFileSync(new URL('../cloudflare/src/finance-postgres.ts', import.meta.url), 'utf8');

test('institution treasury V2 provisions semantic accounts and a single default', () => {
  assert.match(migration, /account_type, is_default_settlement/);
  assert.match(migration, /account_type = 3 AND is_default_settlement/);
  assert.match(migration, /VALUES[\s\S]*\(NEW\.economic_id, 1, 4/);
  assert.match(migration, /VALUES[\s\S]*\(NEW\.economic_id, 1, 5/);
  assert.match(migration, /owner_registry_institution_accounts/);
  assert.match(institutions, /economic_accounts/);
  assert.doesNotMatch(institutions, /UPDATE (cities|corporations) SET treasury/);
  assert.doesNotMatch(finance, /UPDATE cities SET treasury|UPDATE corporations SET treasury/);
});
