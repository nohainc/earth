import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync('db/migrations/002_communities_v2.sql', 'utf8');
const hardeningMigration = fs.readFileSync('db/migrations/003_community_v2_hardening.sql', 'utf8');
const service = fs.readFileSync('cloudflare/src/communities-postgres.ts', 'utf8');
const routes = fs.readFileSync('cloudflare/src/community-routes.ts', 'utf8');
const communications = fs.readFileSync('cloudflare/src/communications-postgres.ts', 'utf8');
const realtime = fs.readFileSync('cloudflare/src/realtime-protocol.ts', 'utf8');

test('Community V2 schema covers House membership, requests, and duplicate protection', () => {
  for (const table of ['communities', 'community_memberships', 'community_membership_requests']) assert.match(migration, new RegExp(`CREATE TABLE ${table}`));
  assert.match(migration, /PRIMARY KEY \(community_id, house_id\)/);
  assert.match(migration, /community_membership_requests_pending_uq/);
  assert.match(migration, /WHERE status = 'PENDING'/);
  assert.match(migration, /CHECK \(role IN \('OWNER', 'MODERATOR', 'MEMBER'\)\)/);
  assert.doesNotMatch(migration, /community_(?:contributions|balances|resources|economic_accounts)/);
});

test('Community names are unique only among active communities', () => {
  assert.match(hardeningMigration, /DROP CONSTRAINT IF EXISTS communities_normalized_name_key/);
  assert.match(hardeningMigration, /CREATE UNIQUE INDEX communities_active_normalized_name_uq/);
  assert.match(hardeningMigration, /ON communities \(normalized_name\)[\s\S]*WHERE status = 'ACTIVE'/);
});

test('Community mutations are House-principal, Human-actor transactions', () => {
  assert.match(service, /repo\.transaction/);
  assert.match(service, /correlationId/);
  assert.match(service, /alreadyProcessed: true/);
  assert.match(service, /COMMUNITY_CREATED/);
  assert.match(service, /INSERT INTO comm_channels/);
  assert.match(service, /INSERT INTO community_memberships/);
  assert.match(service, /assertActor\(tx, input\.houseId, input\.humanId\)/);
  assert.match(service, /FOR UPDATE/);
  assert.match(service, /pg_advisory_xact_lock/);
  assert.match(service, /ON CONFLICT \(community_id,house_id\)/);
  assert.match(service, /status='LEFT'/);
  assert.match(service, /status='REMOVED'/);
  assert.match(service, /COMMUNITY_JOIN_APPROVED|COMMUNITY_JOIN_REJECTED/);
  assert.match(service, /COMMUNITY_ROLE_CHANGED/);
  assert.match(service, /COMMUNITY_DISBANDED/);
  assert.doesNotMatch(service, /account_balances|resource_balances|economic_accounts|owner_registry/);
});

test('Community authorization protects managers and the last Owner', () => {
  assert.match(service, /role !== 'OWNER' && role !== 'MODERATOR'/);
  assert.match(service, /The last owner cannot leave/);
  assert.match(service, /The last owner cannot be demoted/);
  assert.match(service, /Owners must be transferred or demoted before removal/);
  assert.match(service, /Moderator cannot manage owners/);
  assert.match(service, /SELECT house_id FROM community_memberships[\s\S]*FOR UPDATE/);
  assert.match(routes, /join\|leave/);
  assert.match(routes, /approve\|reject/);
  assert.match(routes, /request\.method === 'PATCH'/);
  assert.match(routes, /request\.method === 'DELETE'/);
});

test('Community actions integrate events, notifications, outbox, and realtime', () => {
  assert.match(service, /writeGameEvent/);
  assert.match(service, /createNotification/);
  assert.match(service, /enqueueOutbox/);
  assert.match(service, /topic: 'communities'/);
  assert.match(realtime, /'communities'/);
  assert.match(communications, /ch\.scope = 'community'/);
  assert.match(communications, /cm\.status = 'ACTIVE'/);
  assert.match(communications, /c\.status = 'ACTIVE'/);
  assert.doesNotMatch(service, /contribut/);
});

test('Community API exposes no legacy membership or economic actions', () => {
  assert.doesNotMatch(routes, /applicationQuestion|admissionPolicy|targetHumanId|contribution/);
  assert.doesNotMatch(routes, /members\/\(\[\^\/\]\+\)\/role/);
  assert.match(routes, /targetHouseId/);
});

test('Community reads expose one server-computed viewer state', () => {
  assert.match(service, /viewer_request_status/);
  assert.match(service, /canApproveRequests/);
  assert.match(service, /canChangeRoles/);
  assert.match(service, /canDisband/);
  assert.match(service, /LEFT JOIN LATERAL/);
  assert.match(service, /membership === 'mine'/);
});

test('Community creation has explicit HTTP and transaction safety contracts', () => {
  assert.match(routes, /request\.method === 'POST'/);
  assert.match(routes, /errorResponse\(error, correlationId/);
  assert.match(service, /repo\.transaction\(async \(tx\)/);
  assert.match(service, /pg_advisory_xact_lock\(hashtext\(\$1\)\)/);
  assert.match(service, /event_type='COMMUNITY_CREATED'/);
  assert.match(service, /INSERT INTO comm_channels/);
  assert.match(service, /INSERT INTO community_memberships/);
  assert.match(service, /createGameEvent\(tx/);
});
