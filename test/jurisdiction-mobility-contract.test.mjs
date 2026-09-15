import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { resolveNexus } from '../cloudflare/src/jurisdiction.ts';

test('jurisdiction resolver keeps residence and asset location independent', () => {
  assert.equal(resolveNexus({ nexusType: 'RESIDENCE', residenceTerritoryId: 'T1', assetTerritoryId: 'T2' }), 'T1');
  assert.equal(resolveNexus({ nexusType: 'ASSET_LOCATION', residenceTerritoryId: 'T1', assetTerritoryId: 'T2' }), 'T2');
  assert.equal(resolveNexus({ nexusType: 'EARTH', residenceTerritoryId: 'T1' }), 'EARTH');
});

test('mobility migration records nexus and preserves remote asset jurisdiction', () => {
  const migration = fs.readFileSync('db/migrations/046_jurisdiction_nexus_rules.sql', 'utf8');
  assert.match(migration, /nexus_type/);
  assert.match(migration, /CREATE TABLE IF NOT EXISTS asset_jurisdictions/);
  assert.doesNotMatch(migration, /ON DELETE CASCADE/i);
});

test('human death expires personal office authority while House identity persists', () => {
  const lifecycle = fs.readFileSync('cloudflare/src/lifecycle-postgres.ts', 'utf8');
  assert.match(lifecycle, /organization_office_grants SET status = 'EXPIRED'/);
  assert.match(lifecycle, /principal_type = 'HUMAN'/);
});
