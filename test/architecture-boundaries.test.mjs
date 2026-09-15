import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve('.');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

test('domain boundary types keep authority, actor, payer, owner, location, and state distinct', () => {
  const source = read('cloudflare/src/domain-boundaries.ts');
  assert.match(source, /type AuthorityScope = 'EARTH' \| 'CORPORATION'/);
  assert.match(source, /type ActorType = 'HUMAN' \| 'SYSTEM'/);
  assert.match(source, /'HOUSE'/);
  assert.match(source, /'BANK'/);
  assert.doesNotMatch(source, /'CITY'|TERRITORY.*EconomicPrincipal|BUILDING.*EconomicPrincipal/);
});

test('schema prevents geographic and representative objects from becoming economic principals', () => {
  const schema = read('db/baseline/01_schema.sql');
  assert.match(schema, /owner_type TEXT NOT NULL CHECK \(owner_type IN \('EARTH','CORPORATION','HOUSE','BANK','SYSTEM','ORGANIZATION'\)\)/);
  assert.doesNotMatch(schema, /owner_type[^\n]*\bTERRITORY\b/i);
  assert.doesNotMatch(schema, /owner_type[^\n]*\bBUILDING\b/i);
  assert.doesNotMatch(schema, /owner_type[^\n]*\bHUMAN\b/i);
  assert.match(schema, /buildings[\s\S]*territory_id TEXT NOT NULL REFERENCES territories\(id\)/);
});

test('governance and taxation have only EARTH and Corporation scope', () => {
  const schema = read('db/baseline/01_schema.sql');
  const governance = read('cloudflare/src/governance-v3-postgres.ts');
  assert.match(schema, /scope IN \('EARTH','CORPORATION'\)/);
  assert.match(governance, /EARTH|CORPORATION/);
  assert.doesNotMatch(schema, /scope IN \([^)]*CITY/i);
  assert.doesNotMatch(governance, /\bCITY\b|city_id|cities/i);
});

test('new canonical domain code cannot introduce City as a domain object', () => {
  const files = [
    'cloudflare/src/domain-boundaries.ts',
    'cloudflare/src/territory-capacity-postgres.ts',
    'cloudflare/src/territory-settlement-postgres.ts',
    'cloudflare/src/corporation-fiscal-postgres.ts',
    'cloudflare/src/governance-v3-postgres.ts',
  ];
  for (const file of files) {
    assert.doesNotMatch(read(file), /\bCITY\b|\bcities\b|\bcity_id\b/i, file);
  }
});
