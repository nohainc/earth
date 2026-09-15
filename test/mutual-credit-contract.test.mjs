import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';

const migration = fs.readFileSync('db/migrations/050_mutual_credit_networks.sql', 'utf8');
const service = fs.readFileSync('cloudflare/src/mutual-credit-postgres.ts', 'utf8');
const routes = fs.readFileSync('cloudflare/src/read-model-routes.ts', 'utf8');
const features = fs.readFileSync('cloudflare/src/feature-config.ts', 'utf8');

test('mutual credit is an isolated, feature-gated claim system', () => {
  assert.match(migration, /CREATE TABLE mutual_credit_networks/);
  assert.match(migration, /CREATE TABLE mutual_credit_members/);
  assert.match(migration, /CREATE TABLE mutual_credit_transfers/);
  assert.match(migration, /CREATE TABLE mutual_credit_guarantees/);
  assert.match(migration, /CREATE TABLE mutual_credit_defaults/);
  assert.match(migration, /CHECK \(from_house_id <> to_house_id\)/);
  assert.doesNotMatch(service, /earth_post_transaction|economic_accounts|global CREDIT/i);
  assert.match(service, /position_units = position_units -/);
  assert.match(service, /Transfer exceeds member credit limit/);
  assert.match(service, /positionsReconcile/);
  assert.match(service, /addMutualCreditGuarantee/);
  assert.match(routes, /FEATURE_MUTUAL_CREDIT|mutualCredit/);
  assert.match(features, /mutualCredit: false/);
});

test('mutual credit routes expose idempotent network, membership, and transfer operations', () => {
  for (const fragment of [
    "url.pathname === '/api/mutual-credit/networks'",
    "mutualCreditJoin = url.pathname.match",
    "mutualCreditTransfer = url.pathname.match",
    "mutualCreditGuarantee = url.pathname.match",
  ]) assert.match(routes, new RegExp(fragment.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  assert.match(service, /correlation_id = \$1/);
  assert.match(service, /resolveOrganizationAuthority|organization_memberships/);
});
