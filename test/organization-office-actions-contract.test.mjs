import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('organization offices support membership-aware appointment, resignation, and succession-safe authority', () => {
  const authority = fs.readFileSync('cloudflare/src/organization-authority.ts', 'utf8');
  const routes = fs.readFileSync('cloudflare/src/organizations-routes.ts', 'utf8');
  const lifecycle = fs.readFileSync('cloudflare/src/lifecycle-postgres.ts', 'utf8');
  const migration = fs.readFileSync('db/migrations/034_organization_offices.sql', 'utf8');
  assert.match(authority, /appointOrganizationOffice/);
  assert.match(authority, /resignOrganizationOffice/);
  assert.match(authority, /resolveOrganizationAuthority\(tx/);
  assert.match(authority, /organization_memberships/);
  assert.match(authority, /ONFLICT|organization_office_grants/);
  assert.match(routes, /offices\\\/\(EXECUTIVE\|TREASURER\|GOVERNOR\|OPERATOR\|RESEARCHER\)/);
  assert.match(lifecycle, /organization_office_grants SET status = 'EXPIRED'/);
  assert.match(migration, /one_human_holder/);
});
