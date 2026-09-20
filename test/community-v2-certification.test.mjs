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
  assert.match(service, /transfer ownership or disband/);
  assert.match(service, /Transfer ownership before changing the owner role/);
  assert.match(service, /Owners must be transferred or demoted before removal/);
  assert.match(service, /Only the Community owner can change roles/);
  assert.match(service, /transferCommunityOwnership/);
  assert.match(service, /COMMUNITY_OWNERSHIP_TRANSFERRED/);
  assert.match(routes, /ownership.*transfer/);
  assert.match(service, /SELECT house_id,role,status FROM community_memberships[\s\S]*FOR UPDATE/);
  assert.match(routes, /join\|leave/);
  assert.match(routes, /approve\|reject/);
  assert.match(routes, /request\.method === 'PATCH'/);
  assert.match(routes, /request\.method === 'DELETE'/);
  assert.match(routes, /sensitiveActionAllowed/);
  assert.match(routes, /Recent authentication or MFA is required/);
  assert.match(service, /existing\.rows\[0\]\.role === 'OWNER'/);
});

test('Community ownership has one atomic owner and moderator delegation', () => {
  const transferMigration = fs.readFileSync('db/migrations/176_community_single_owner.sql', 'utf8');
  assert.match(transferMigration, /ROW_NUMBER\(\)/);
  assert.match(transferMigration, /community_one_active_owner_uq/);
  assert.match(transferMigration, /role = 'MODERATOR'/);
  assert.match(service, /UPDATE community_memberships SET role=CASE/);
  assert.match(service, /!\['MODERATOR', 'MEMBER'\]\.includes\(input\.role\)/);
  assert.doesNotMatch(routes, /role\?: 'OWNER' \| 'MODERATOR' \| 'MEMBER'/);
  assert.match(service, /actorHouseId === input\.targetHouseId/);
  assert.match(service, /ORDER BY house_id FOR UPDATE/);
  assert.match(service, /UPDATE community_memberships SET role=CASE/);
});

test('Community membership mutations are idempotent and disband cleanup is atomic', () => {
  assert.match(service, /event_type IN \('COMMUNITY_JOINED','COMMUNITY_JOIN_REQUESTED','COMMUNITY_LEFT'\)/);
  assert.match(service, /alreadyProcessed: true, status/);
  assert.match(service, /ON CONFLICT \(correlation_id\) DO NOTHING/);
  assert.match(service, /UPDATE community_membership_requests SET status='CANCELLED'/);
  assert.match(service, /UPDATE community_memberships SET status='REMOVED'/);
  assert.match(service, /repo\.transaction\(async \(tx\)/);
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

test('Community roster and admission requests use canonical House DTOs', () => {
  assert.match(service, /h\.house_name/);
  assert.match(service, /h\.current_human_id/);
  assert.match(service, /hu\.display_name AS current_human_name/);
  assert.match(service, /r\.message AS application_message/);
  assert.match(service, /r\.decision_note/);
  assert.match(service, /current_human_name/);
  assert.match(service, /CommunityMemberRosterEntry/);
  assert.match(service, /CommunityMembershipRequestDto/);
  assert.match(service, /CommunityCapabilityMatrix/);
  assert.match(service, /capabilities/);
  const api = fs.readFileSync('flutter_client/lib/core/api/earth_api_institutions.dart', 'utf8');
  const models = fs.readFileSync('flutter_client/lib/core/models/community_models.dart', 'utf8');
  const panel = fs.readFileSync('flutter_client/lib/features/institutions/institutions_panels.dart', 'utf8');
  const dialogs = fs.readFileSync('flutter_client/lib/features/institutions/institutions_dialogs.dart', 'utf8');
  assert.match(api, /Future<CommunityMembersResponse> listCommunityMembers/);
  assert.match(api, /Future<CommunityMembershipRequestsResponse> listCommunityRequests/);
  assert.match(models, /class CommunityMember/);
  assert.match(models, /class CommunityMembershipRequest/);
  assert.match(panel, /m\.houseId/);
  assert.match(dialogs, /m\.currentHumanName/);
  assert.match(dialogs, /req\.applicationMessage/);
  assert.doesNotMatch(`${panel}\n${dialogs}`, /m\['human_id'\]|m\['human_name'\]|req\['human_id'\]|req\['human_name'\]/);
  assert.doesNotMatch(panel, /'FOUNDER'/);
});

test('Community membership is House-owned across Human succession', () => {
  const migration = fs.readFileSync('db/migrations/002_communities_v2.sql', 'utf8');
  const lifecycle = fs.readFileSync('cloudflare/src/lifecycle-postgres.ts', 'utf8');
  const models = fs.readFileSync('flutter_client/lib/core/models/community_models.dart', 'utf8');
  assert.match(migration, /PRIMARY KEY \(community_id, house_id\)/);
  assert.match(service, /community_memberships[\s\S]*cm\.house_id/);
  assert.match(service, /JOIN houses h ON h\.id=cm\.house_id/);
  assert.match(service, /h\.current_human_id AS human_id/);
  const mortality = lifecycle.slice(
    lifecycle.indexOf('export async function processHouseMortality'),
    lifecycle.indexOf('export async function activatePendingHouseSuccessors'),
  );
  assert.doesNotMatch(mortality, /community_memberships/);
  assert.match(models, /class CommunitySummary/);
  assert.match(models, /class CommunityDetail extends CommunitySummary/);
  assert.match(models, /class CommunityMember/);
  assert.match(models, /class CommunityViewerPermissions/);
  assert.match(models, /class CommunityCapabilityMatrix/);
});

test('V5 Communities are public and admission-only gated', () => {
  const migration = fs.readFileSync('db/migrations/175_communities_public_visibility.sql', 'utf8');
  assert.match(migration, /SET visibility = 'PUBLIC'/);
  assert.match(migration, /CHECK \(visibility = 'PUBLIC'\)/);
  assert.doesNotMatch(service, /visibility === 'PRIVATE'/);
  assert.doesNotMatch(routes, /visibility\?: 'PUBLIC' \| 'PRIVATE'/);
  assert.match(service, /c\.visibility='PUBLIC'/);
  assert.match(service, /Communities are public/);
  assert.match(service, /requestStatus !== 'PENDING'/);
});

test('Community request lifecycle preserves application text and resolves current applicants', () => {
  const models = fs.readFileSync('flutter_client/lib/core/models/community_models.dart', 'utf8');
  assert.doesNotMatch(service, /UPDATE community_membership_requests SET status='REJECTED',message=CASE WHEN/);
  assert.match(service, /decision_note=\$1/);
  assert.match(service, /SELECT current_human_id AS human_id FROM houses WHERE id=\$1/);
  assert.match(service, /cancelCommunityMembershipRequest/);
  assert.match(service, /COMMUNITY_JOIN_CANCELLED/);
  assert.match(routes, /requests.*cancel/);
  assert.match(models, /decisionNote/);
  assert.match(models, /requestId/);
  assert.match(service, /SELECT current_human_id AS human_id FROM houses WHERE id=\$1/);
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
