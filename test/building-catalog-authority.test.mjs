import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('construction and upgrade runtime paths are database-catalog driven', () => {
  const realEstate = fs.readFileSync('cloudflare/src/real-estate-postgres.ts', 'utf8');
  const governance = fs.readFileSync('cloudflare/src/governance-postgres.ts', 'utf8');
  assert.doesNotMatch(realEstate, /BUILDING_CATALOG/);
  assert.doesNotMatch(realEstate, /4800\s*\*\s*nextTier/);
  assert.doesNotMatch(realEstate, /Math\.pow\([^\n]*tier/);
  assert.doesNotMatch(governance, /BUILDING_CATALOG/);
  assert.match(realEstate, /FROM building_catalog WHERE id = \$1/);
});
