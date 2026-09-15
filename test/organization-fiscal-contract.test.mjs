import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('Organization finance reuses Economy V2 accounts while separating budget authority from cash movement', () => {
  const migration = fs.readFileSync('db/migrations/028_organization_economy.sql', 'utf8');
  const service = fs.readFileSync('cloudflare/src/organization-fiscal-postgres.ts', 'utf8');
  const routes = fs.readFileSync('cloudflare/src/organizations-routes.ts', 'utf8');
  assert.match(migration, /owner_registry_owner_type_check/);
  assert.match(migration, /owner_type, account_type, allowed_asset_kind/);
  assert.match(migration, /organization_economies/);
  assert.match(migration, /organization_budget_lines/);
  assert.match(migration, /authorized_units >= committed_units \+ spent_units/);
  assert.match(service, /Organization is not eligible for an economy/);
  assert.match(service, /ECONOMIC_OWNER/);
  assert.match(service, /earth_post_transaction/);
  assert.match(service, /Budget authority exceeded/);
  assert.match(service, /Organization cash balance is insufficient/);
  assert.match(routes, /provisionMatch/);
  assert.match(routes, /spendMatch/);
});
