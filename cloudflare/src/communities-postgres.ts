import type { PostgresRepository } from './repository.ts';
import { createGameEvent as writeGameEvent, type GameEventInput } from './game-events-postgres.ts';
import { createNotification } from './notifications-postgres.ts';
import { enqueueOutbox } from './outbox-postgres.ts';
import { earthError } from './errors.ts';

type CommunityRole = 'OWNER' | 'MODERATOR' | 'MEMBER';
type MembershipAction = 'join' | 'leave' | 'remove';
const newId = (prefix: string) => `${prefix}-${crypto.randomUUID()}`;
const cleanName = (name: string) => name.trim().normalize('NFKC').replace(/\s+/g, ' ');
const normalizedName = (name: string) => cleanName(name).toLowerCase();

async function createGameEvent(repo: PostgresRepository, input: GameEventInput) {
  await writeGameEvent(repo, input);
  await enqueueOutbox(repo, {
    eventKey: input.correlationId ?? input.id,
    topic: 'communities',
    aggregateType: 'community',
    aggregateId: input.subjectId ?? input.id,
    payload: { eventType: input.eventType, gameDay: input.gameDay, gameMinute: input.gameMinute ?? null },
  });
}

async function getClock(repo: PostgresRepository) {
  const result = await repo.query<{ game_day: number; game_minute: number }>(`SELECT game_day, game_minute FROM world_state WHERE id='WORLD' FOR UPDATE`);
  if (!result.rows[0]) throw earthError('SERVICE_UNAVAILABLE', 'World clock is not configured.');
  return { gameDay: Number(result.rows[0].game_day), gameMinute: Number(result.rows[0].game_minute) };
}

async function assertActor(repo: PostgresRepository, houseId: string, humanId: string) {
  const result = await repo.query(`SELECT h.id FROM humans h JOIN houses hs ON hs.id=h.house_id WHERE h.id=$1 AND h.house_id=$2 AND h.status='ACTIVE' AND hs.status='ACTIVE' FOR UPDATE`, [humanId, houseId]);
  if (!result.rows[0]) throw earthError('FORBIDDEN', 'The current Human does not belong to this House.');
}

async function loadCommunity(repo: PostgresRepository, communityId: string, lock = false) {
  const result = await repo.query(`SELECT c.*, (SELECT COUNT(*)::int FROM community_memberships cm WHERE cm.community_id=c.id AND cm.status='ACTIVE') AS member_count, (SELECT h.house_name FROM houses h WHERE h.id=c.founder_house_id) AS founder_house_name FROM communities c WHERE c.id=$1 ${lock ? 'FOR UPDATE OF c' : ''}`, [communityId]);
  if (!result.rows[0]) throw earthError('NOT_FOUND', 'Community not found.');
  return result.rows[0] as Record<string, any>;
}

function withViewerState(row: Record<string, any>, houseId?: string) {
  const membershipStatus = row.viewer_membership_status === 'ACTIVE' ? 'ACTIVE' : null;
  const role = membershipStatus ? row.viewer_role : null;
  const requestStatus = membershipStatus ? null : (row.viewer_request_status ?? null);
  const active = row.status === 'ACTIVE';
  const ownerCount = Number(row.active_owner_count ?? 0);
  const manager = active && (role === 'OWNER' || role === 'MODERATOR');
  const owner = active && role === 'OWNER';
  const { viewer_role: _viewerRole, viewer_membership_status: _viewerMembershipStatus, viewer_request_status: _viewerRequestStatus, active_owner_count: _activeOwnerCount, ...community } = row;
  return {
    ...community,
    member_count: Number(row.member_count ?? 0),
    viewer: {
      membershipStatus,
      role,
      requestStatus,
      canJoin: Boolean(houseId) && active && !membershipStatus && requestStatus !== 'PENDING',
      canLeave: Boolean(membershipStatus) && (!owner || ownerCount > 1),
      canEdit: manager,
      canManageMembers: manager,
      canApproveRequests: manager,
      canChangeRoles: owner,
      canDisband: owner,
    },
  };
}

async function getRole(repo: PostgresRepository, communityId: string, houseId: string, lock = false): Promise<CommunityRole | null> {
  const result = await repo.query<{ role: CommunityRole; status: string }>(`SELECT role,status FROM community_memberships WHERE community_id=$1 AND house_id=$2 ${lock ? 'FOR UPDATE' : ''}`, [communityId, houseId]);
  return result.rows[0]?.status === 'ACTIVE' ? result.rows[0].role : null;
}

function requireManager(role: CommunityRole | null) {
  if (role !== 'OWNER' && role !== 'MODERATOR') throw earthError('FORBIDDEN', 'Community owner or moderator permission required.');
}

async function addNotification(repo: PostgresRepository, houseId: string, humanId: string, communityId: string, type: string, title: string, body: string, day: number, minute: number, correlationId: string) {
  await createNotification(repo, { id: newId('NOTIFICATION'), houseId, humanId, notificationType: type, title, body, entityType: 'COMMUNITY', entityId: communityId, gameDay: day, gameMinute: minute, correlationId });
}

async function notifyManagers(repo: PostgresRepository, communityId: string, communityName: string, day: number, minute: number, correlationId: string) {
  const managers = await repo.query<{ house_id: string; human_id: string }>(`SELECT cm.house_id,h.current_human_id AS human_id FROM community_memberships cm JOIN houses h ON h.id=cm.house_id WHERE cm.community_id=$1 AND cm.status='ACTIVE' AND cm.role IN ('OWNER','MODERATOR') AND h.current_human_id IS NOT NULL`, [communityId]);
  for (const manager of managers.rows) await addNotification(repo, manager.house_id, manager.human_id, communityId, 'COMMUNITY_JOIN_REQUESTED', 'New community membership request', `${communityName} has a new House membership request.`, day, minute, `${correlationId}:${manager.house_id}`);
}

export async function listCommunities(repo: PostgresRepository, houseId?: string, membership: 'mine' | undefined = undefined) {
  const result = await repo.query(`
    SELECT c.*,
      (SELECT COUNT(*)::int FROM community_memberships all_cm WHERE all_cm.community_id=c.id AND all_cm.status='ACTIVE') AS member_count,
      (SELECT COUNT(*)::int FROM community_memberships owners WHERE owners.community_id=c.id AND owners.status='ACTIVE' AND owners.role='OWNER') AS active_owner_count,
      (SELECT h.house_name FROM houses h WHERE h.id=c.founder_house_id) AS founder_house_name,
      cm.role AS viewer_role,
      cm.status AS viewer_membership_status,
      pending.status AS viewer_request_status
    FROM communities c
    LEFT JOIN community_memberships cm ON cm.community_id=c.id AND cm.house_id=$1
    LEFT JOIN LATERAL (
      SELECT r.status
      FROM community_membership_requests r
      WHERE r.community_id=c.id AND r.house_id=$1
      ORDER BY r.created_at DESC
      LIMIT 1
    ) pending ON true
    WHERE c.status='ACTIVE' ${membership === 'mine' ? "AND cm.status='ACTIVE'" : ''}
    ORDER BY c.created_at DESC`, [houseId ?? null]);
  return { ok: true, communities: result.rows.map((row) => withViewerState(row, houseId)) };
}

export async function getCommunity(repo: PostgresRepository, communityId: string, houseId: string) {
  const result = await repo.query(`
    SELECT c.*,
      (SELECT COUNT(*)::int FROM community_memberships all_cm WHERE all_cm.community_id=c.id AND all_cm.status='ACTIVE') AS member_count,
      (SELECT COUNT(*)::int FROM community_memberships owners WHERE owners.community_id=c.id AND owners.status='ACTIVE' AND owners.role='OWNER') AS active_owner_count,
      (SELECT h.house_name FROM houses h WHERE h.id=c.founder_house_id) AS founder_house_name,
      cm.role AS viewer_role,
      cm.status AS viewer_membership_status,
      pending.status AS viewer_request_status
    FROM communities c
    LEFT JOIN community_memberships cm ON cm.community_id=c.id AND cm.house_id=$2
    LEFT JOIN LATERAL (
      SELECT r.status
      FROM community_membership_requests r
      WHERE r.community_id=c.id AND r.house_id=$2
      ORDER BY r.created_at DESC
      LIMIT 1
    ) pending ON true
    WHERE c.id=$1`, [communityId, houseId]);
  if (!result.rows[0]) throw earthError('NOT_FOUND', 'Community not found.');
  const community = withViewerState(result.rows[0], houseId);
  if (community.visibility === 'PRIVATE' && !community.viewer.membershipStatus) throw earthError('FORBIDDEN', 'Community membership required.');
  return { ok: true, community };
}

export async function createCommunity(repo: PostgresRepository, input: { houseId: string; humanId: string; name: string; description?: string; visibility?: string; joinPolicy?: string; correlationId: string }) {
  return repo.transaction(async (tx) => {
    await tx.query(`SELECT pg_advisory_xact_lock(hashtext($1))`, [`community-create:${input.correlationId}`]);
    const prior = await tx.query<{ subject_id: string }>(`SELECT subject_id FROM game_events WHERE correlation_id=$1 AND event_type='COMMUNITY_CREATED'`, [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, community: await loadCommunity(tx, prior.rows[0].subject_id) };
    await assertActor(tx, input.houseId, input.humanId);
    const name = cleanName(input.name); const description = input.description?.trim() ?? '';
    if (name.length < 3 || name.length > 80) throw earthError('VALIDATION_ERROR', 'Community name must be 3–80 characters.', { field: 'name' });
    if (description.length > 5000) throw earthError('VALIDATION_ERROR', 'Community description is too long.', { field: 'description' });
    const visibility = input.visibility ?? 'PUBLIC'; const joinPolicy = input.joinPolicy ?? 'OPEN';
    if (!['PUBLIC', 'PRIVATE'].includes(visibility) || !['OPEN', 'REQUEST'].includes(joinPolicy)) throw earthError('VALIDATION_ERROR', 'Invalid community rules.');
    const time = await getClock(tx); const communityId = newId('COMMUNITY');
    await tx.query(`INSERT INTO communities (id,name,normalized_name,description,visibility,join_policy,founder_house_id,created_by_human_id,created_game_day,created_game_minute) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`, [communityId, name, normalizedName(name), description, visibility, joinPolicy, input.houseId, input.humanId, time.gameDay, time.gameMinute]);
    await tx.query(`INSERT INTO comm_channels (id,scope,scope_id,name,description) VALUES ($1,'community',$2,$3,$4)`, [`channel-community-${communityId}`, communityId, name, `Community channel for ${name}`]);
    await tx.query(`INSERT INTO community_memberships (community_id,house_id,role,joined_by_human_id,joined_game_day,joined_game_minute) VALUES ($1,$2,'OWNER',$3,$4,$5)`, [communityId, input.houseId, input.humanId, time.gameDay, time.gameMinute]);
    await createGameEvent(tx, { id: newId('EVENT'), category: 'INSTITUTION', eventType: 'COMMUNITY_CREATED', gameDay: time.gameDay, gameMinute: time.gameMinute, actorHouseId: input.houseId, actorHumanId: input.humanId, subjectType: 'COMMUNITY', subjectId: communityId, title: `${name} formed`, details: { visibility, joinPolicy }, correlationId: input.correlationId });
    return { ok: true, alreadyProcessed: false, community: await loadCommunity(tx, communityId) };
  });
}

export async function updateCommunity(repo: PostgresRepository, input: { communityId: string; houseId: string; humanId: string; name?: string; description?: string; visibility?: string; joinPolicy?: string }) {
  return repo.transaction(async (tx) => {
    await assertActor(tx, input.houseId, input.humanId); await loadCommunity(tx, input.communityId, true); requireManager(await getRole(tx, input.communityId, input.houseId, true));
    const fields: string[] = []; const values: unknown[] = [];
    const add = (field: string, value: unknown) => { fields.push(`${field}=$${values.length + 1}`); values.push(value); };
    if (input.name !== undefined) { const name = cleanName(input.name); if (name.length < 3 || name.length > 80) throw earthError('VALIDATION_ERROR', 'Community name must be 3–80 characters.', { field: 'name' }); add('name', name); add('normalized_name', normalizedName(name)); }
    if (input.description !== undefined) { if (input.description.length > 5000) throw earthError('VALIDATION_ERROR', 'Community description is too long.', { field: 'description' }); add('description', input.description.trim()); }
    if (input.visibility !== undefined) { if (!['PUBLIC', 'PRIVATE'].includes(input.visibility)) throw earthError('VALIDATION_ERROR', 'Invalid visibility.', { field: 'visibility' }); add('visibility', input.visibility); }
    if (input.joinPolicy !== undefined) { if (!['OPEN', 'REQUEST'].includes(input.joinPolicy)) throw earthError('VALIDATION_ERROR', 'Invalid join policy.', { field: 'joinPolicy' }); add('join_policy', input.joinPolicy); }
    if (!fields.length) throw earthError('VALIDATION_ERROR', 'No community fields to update.'); fields.push('updated_at=CURRENT_TIMESTAMP'); values.push(input.communityId);
    await tx.query(`UPDATE communities SET ${fields.join(',')} WHERE id=$${values.length}`, values);
    const time = await getClock(tx);
    await createGameEvent(tx, { id: newId('EVENT'), category: 'INSTITUTION', eventType: 'COMMUNITY_UPDATED', gameDay: time.gameDay, gameMinute: time.gameMinute, actorHouseId: input.houseId, actorHumanId: input.humanId, subjectType: 'COMMUNITY', subjectId: input.communityId, title: 'Community updated', correlationId: `community-update:${input.communityId}:${time.gameDay}:${time.gameMinute}` });
    return { ok: true, community: await loadCommunity(tx, input.communityId) };
  });
}

export async function changeCommunityMembership(repo: PostgresRepository, input: { communityId: string; houseId: string; humanId: string; action: MembershipAction; targetHouseId?: string; applicationMessage?: string; correlationId?: string }) {
  return repo.transaction(async (tx) => {
    await assertActor(tx, input.houseId, input.humanId); const c = await loadCommunity(tx, input.communityId, true); if (c.status !== 'ACTIVE') throw earthError('COMMUNITY_DISBANDED', 'Community is disbanded.');
    if (input.action === 'remove') {
      requireManager(await getRole(tx, input.communityId, input.houseId, true));
      if (!input.targetHouseId || input.targetHouseId === input.houseId) throw earthError('VALIDATION_ERROR', 'A different member House is required.', { field: 'houseId' });
      const target = (await tx.query<{ role: CommunityRole; status: string }>(`SELECT role,status FROM community_memberships WHERE community_id=$1 AND house_id=$2 FOR UPDATE`, [input.communityId, input.targetHouseId])).rows[0];
      if (!target || target.status !== 'ACTIVE') throw earthError('NOT_FOUND', 'Target House is not an active member.');
      if (target.role === 'OWNER') throw earthError('FORBIDDEN', 'Owners must be transferred or demoted before removal.');
      await tx.query(`UPDATE community_memberships SET status='REMOVED',left_at=CURRENT_TIMESTAMP,updated_at=CURRENT_TIMESTAMP WHERE community_id=$1 AND house_id=$2`, [input.communityId, input.targetHouseId]);
      const time = await getClock(tx);
      await createGameEvent(tx, { id: newId('EVENT'), category: 'INSTITUTION', eventType: 'COMMUNITY_MEMBER_REMOVED', gameDay: time.gameDay, gameMinute: time.gameMinute, actorHouseId: input.houseId, actorHumanId: input.humanId, subjectType: 'COMMUNITY', subjectId: input.communityId, title: 'House removed from community', details: { targetHouseId: input.targetHouseId }, correlationId: `community-remove:${input.communityId}:${input.targetHouseId}:${time.gameDay}` });
      const targetHuman = (await tx.query<{ human_id: string }>(`SELECT current_human_id AS human_id FROM houses WHERE id=$1`, [input.targetHouseId])).rows[0]?.human_id;
      if (targetHuman) await addNotification(tx, input.targetHouseId, targetHuman, input.communityId, 'COMMUNITY_MEMBER_REMOVED', 'Removed from community', 'Your House was removed from the community.', time.gameDay, time.gameMinute, `community-remove-notification:${input.communityId}:${input.targetHouseId}:${time.gameDay}`);
      return { ok: true, status: 'REMOVED' };
    }
    const time = await getClock(tx); const existing = await tx.query<{ role: CommunityRole; status: string }>(`SELECT role,status FROM community_memberships WHERE community_id=$1 AND house_id=$2 FOR UPDATE`, [input.communityId, input.houseId]);
    if (input.action === 'leave') {
      if (!existing.rows[0] || existing.rows[0].status !== 'ACTIVE') throw earthError('NOT_FOUND', 'House is not an active member.');
      if (existing.rows[0].role === 'OWNER') { const owners = await tx.query(`SELECT house_id FROM community_memberships WHERE community_id=$1 AND role='OWNER' AND status='ACTIVE' FOR UPDATE`, [input.communityId]); if (owners.rows.length < 2) throw earthError('COMMUNITY_LAST_OWNER', 'The last owner cannot leave.'); }
      await tx.query(`UPDATE community_memberships SET status='LEFT',left_at=CURRENT_TIMESTAMP,updated_at=CURRENT_TIMESTAMP WHERE community_id=$1 AND house_id=$2`, [input.communityId, input.houseId]);
      await createGameEvent(tx, { id: newId('EVENT'), category: 'AFFILIATION', eventType: 'COMMUNITY_LEFT', gameDay: time.gameDay, gameMinute: time.gameMinute, actorHouseId: input.houseId, actorHumanId: input.humanId, subjectType: 'COMMUNITY', subjectId: input.communityId, title: 'House left community', correlationId: `community-leave:${input.communityId}:${input.houseId}:${time.gameDay}` });
      return { ok: true, status: 'LEFT' };
    }
    if (existing.rows[0]?.status === 'ACTIVE') throw earthError('COMMUNITY_ALREADY_MEMBER', 'House is already an active member.');
    if (c.join_policy === 'OPEN') {
      await tx.query(`INSERT INTO community_memberships (community_id,house_id,role,status,joined_by_human_id,joined_game_day,joined_game_minute,left_at) VALUES ($1,$2,'MEMBER','ACTIVE',$3,$4,$5,NULL) ON CONFLICT (community_id,house_id) DO UPDATE SET role='MEMBER',status='ACTIVE',joined_by_human_id=EXCLUDED.joined_by_human_id,joined_game_day=EXCLUDED.joined_game_day,joined_game_minute=EXCLUDED.joined_game_minute,left_at=NULL,updated_at=CURRENT_TIMESTAMP`, [input.communityId, input.houseId, input.humanId, time.gameDay, time.gameMinute]);
      await createGameEvent(tx, { id: newId('EVENT'), category: 'AFFILIATION', eventType: 'COMMUNITY_JOINED', gameDay: time.gameDay, gameMinute: time.gameMinute, actorHouseId: input.houseId, actorHumanId: input.humanId, subjectType: 'COMMUNITY', subjectId: input.communityId, title: 'House joined community', correlationId: input.correlationId ?? `community-join:${input.communityId}:${input.houseId}:${time.gameDay}` });
      return { ok: true, status: 'ACTIVE' };
    }
    const correlationId = input.correlationId ?? `community-request:${input.communityId}:${input.houseId}:${time.gameDay}`;
    const pending = await tx.query(`SELECT * FROM community_membership_requests WHERE community_id=$1 AND house_id=$2 AND status='PENDING' FOR UPDATE`, [input.communityId, input.houseId]);
    if (pending.rows[0]) return { ok: true, alreadyProcessed: true, status: 'PENDING', request: pending.rows[0] };
    const requestId = newId('REQUEST'); await tx.query(`INSERT INTO community_membership_requests (id,community_id,house_id,message,requested_by_human_id,correlation_id,requested_game_day,requested_game_minute) VALUES ($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT (correlation_id) DO NOTHING`, [requestId, input.communityId, input.houseId, input.applicationMessage?.trim().slice(0, 2000) ?? '', input.humanId, correlationId, time.gameDay, time.gameMinute]);
    await createGameEvent(tx, { id: newId('EVENT'), category: 'AFFILIATION', eventType: 'COMMUNITY_JOIN_REQUESTED', gameDay: time.gameDay, gameMinute: time.gameMinute, actorHouseId: input.houseId, actorHumanId: input.humanId, subjectType: 'COMMUNITY', subjectId: input.communityId, title: 'Community membership requested', correlationId: `community-request-event:${correlationId}` });
    await notifyManagers(tx, input.communityId, c.name, time.gameDay, time.gameMinute, `community-request-notification:${correlationId}`);
    return { ok: true, status: 'PENDING', request: (await tx.query(`SELECT * FROM community_membership_requests WHERE correlation_id=$1`, [correlationId])).rows[0] };
  });
}

export async function listCommunityMembers(repo: PostgresRepository, communityId: string, houseId?: string) {
  const c = await loadCommunity(repo, communityId); if (c.visibility === 'PRIVATE' && (!houseId || !(await getRole(repo, communityId, houseId)))) throw earthError('FORBIDDEN', 'Community membership required.');
  const result = await repo.query(`SELECT cm.*,h.house_name,h.current_human_id,hu.display_name AS current_human_name FROM community_memberships cm JOIN houses h ON h.id=cm.house_id LEFT JOIN humans hu ON hu.id=h.current_human_id WHERE cm.community_id=$1 ORDER BY cm.joined_at`, [communityId]);
  return { ok: true, members: result.rows };
}

export async function listCommunityMembershipRequests(repo: PostgresRepository, communityId: string, houseId: string) { requireManager(await getRole(repo, communityId, houseId)); const result = await repo.query(`SELECT * FROM community_membership_requests WHERE community_id=$1 ORDER BY created_at DESC`, [communityId]); return { ok: true, requests: result.rows }; }

export async function decideCommunityMembershipRequest(repo: PostgresRepository, input: { communityId: string; requestId: string; actorHouseId: string; actorHumanId: string; action: 'approve' | 'reject'; rejectionReason?: string }) {
  return repo.transaction(async (tx) => {
    await assertActor(tx, input.actorHouseId, input.actorHumanId); await loadCommunity(tx, input.communityId, true); requireManager(await getRole(tx, input.communityId, input.actorHouseId, true));
    const request = (await tx.query<Record<string, any>>(`SELECT * FROM community_membership_requests WHERE id=$1 AND community_id=$2 FOR UPDATE`, [input.requestId, input.communityId])).rows[0]; if (!request) throw earthError('NOT_FOUND', 'Membership request not found.'); if (request.status !== 'PENDING') throw earthError('CONFLICT', 'Membership request is already decided.');
    const time = await getClock(tx);
    if (input.action === 'approve') { await tx.query(`INSERT INTO community_memberships (community_id,house_id,role,status,joined_by_human_id,joined_game_day,joined_game_minute,left_at) VALUES ($1,$2,'MEMBER','ACTIVE',$3,$4,$5,NULL) ON CONFLICT (community_id,house_id) DO UPDATE SET role='MEMBER',status='ACTIVE',joined_by_human_id=EXCLUDED.joined_by_human_id,joined_game_day=EXCLUDED.joined_game_day,joined_game_minute=EXCLUDED.joined_game_minute,left_at=NULL,updated_at=CURRENT_TIMESTAMP`, [input.communityId, request.house_id, request.requested_by_human_id, time.gameDay, time.gameMinute]); await tx.query(`UPDATE community_membership_requests SET status='APPROVED',decided_by_human_id=$1,decided_at=CURRENT_TIMESTAMP WHERE id=$2`, [input.actorHumanId, input.requestId]); }
    else await tx.query(`UPDATE community_membership_requests SET status='REJECTED',message=CASE WHEN $1='' THEN message ELSE $1 END,decided_by_human_id=$2,decided_at=CURRENT_TIMESTAMP WHERE id=$3`, [input.rejectionReason?.trim().slice(0, 2000) ?? '', input.actorHumanId, input.requestId]);
    await createGameEvent(tx, { id: newId('EVENT'), category: 'AFFILIATION', eventType: input.action === 'approve' ? 'COMMUNITY_JOIN_APPROVED' : 'COMMUNITY_JOIN_REJECTED', gameDay: time.gameDay, gameMinute: time.gameMinute, actorHouseId: input.actorHouseId, actorHumanId: input.actorHumanId, subjectType: 'COMMUNITY', subjectId: input.communityId, title: input.action === 'approve' ? 'House joined community' : 'Community request rejected', details: { affectedHouseId: request.house_id }, correlationId: `community-request-decision:${input.requestId}:${input.action}` });
    await addNotification(tx, request.house_id, request.requested_by_human_id, input.communityId, 'COMMUNITY_REQUEST_DECIDED', input.action === 'approve' ? 'Community request approved' : 'Community request rejected', input.action === 'approve' ? 'Your House joined the community.' : 'Your community request was rejected.', time.gameDay, time.gameMinute, `community-request-notification:${input.requestId}:${input.action}`);
    return { ok: true, status: input.action === 'approve' ? 'APPROVED' : 'REJECTED' };
  });
}

export async function setCommunityMemberRole(repo: PostgresRepository, input: { communityId: string; actorHouseId: string; actorHumanId: string; targetHouseId: string; role: CommunityRole }) {
  return repo.transaction(async (tx) => {
    await assertActor(tx, input.actorHouseId, input.actorHumanId); await loadCommunity(tx, input.communityId, true); const actorRole = await getRole(tx, input.communityId, input.actorHouseId, true); requireManager(actorRole);
    const target = (await tx.query<{ role: CommunityRole; status: string }>(`SELECT role,status FROM community_memberships WHERE community_id=$1 AND house_id=$2 FOR UPDATE`, [input.communityId, input.targetHouseId])).rows[0]; if (!target || target.status !== 'ACTIVE') throw earthError('NOT_FOUND', 'Target House is not an active member.'); if (!['OWNER', 'MODERATOR', 'MEMBER'].includes(input.role)) throw earthError('VALIDATION_ERROR', 'Invalid community role.', { field: 'role' });
    if (actorRole === 'MODERATOR' && (target.role === 'OWNER' || input.role === 'OWNER')) throw earthError('FORBIDDEN', 'Moderator cannot manage owners.');
    if (target.role === 'OWNER' && input.role !== 'OWNER') { const owners = await tx.query(`SELECT house_id FROM community_memberships WHERE community_id=$1 AND role='OWNER' AND status='ACTIVE' FOR UPDATE`, [input.communityId]); if (owners.rows.length < 2) throw earthError('COMMUNITY_LAST_OWNER', 'The last owner cannot be demoted.'); }
    await tx.query(`UPDATE community_memberships SET role=$1,updated_at=CURRENT_TIMESTAMP WHERE community_id=$2 AND house_id=$3`, [input.role, input.communityId, input.targetHouseId]);
    const time = await getClock(tx);
    await createGameEvent(tx, { id: newId('EVENT'), category: 'INSTITUTION', eventType: 'COMMUNITY_ROLE_CHANGED', gameDay: time.gameDay, gameMinute: time.gameMinute, actorHouseId: input.actorHouseId, actorHumanId: input.actorHumanId, subjectType: 'COMMUNITY', subjectId: input.communityId, title: 'Community role changed', details: { targetHouseId: input.targetHouseId, role: input.role }, correlationId: `community-role:${input.communityId}:${input.targetHouseId}:${time.gameDay}:${input.role}` });
    const targetHuman = (await tx.query<{ human_id: string }>(`SELECT current_human_id AS human_id FROM houses WHERE id=$1`, [input.targetHouseId])).rows[0]?.human_id;
    if (targetHuman) await addNotification(tx, input.targetHouseId, targetHuman, input.communityId, 'COMMUNITY_ROLE_CHANGED', 'Community role changed', `Your role is now ${input.role}.`, time.gameDay, time.gameMinute, `community-role-notification:${input.communityId}:${input.targetHouseId}:${time.gameDay}:${input.role}`);
    return { ok: true, role: input.role };
  });
}

export async function disbandCommunity(repo: PostgresRepository, input: { communityId: string; houseId: string; humanId: string }) {
  return repo.transaction(async (tx) => {
    await assertActor(tx, input.houseId, input.humanId); await loadCommunity(tx, input.communityId, true); if ((await getRole(tx, input.communityId, input.houseId, true)) !== 'OWNER') throw earthError('FORBIDDEN', 'Community owner permission required.'); const time = await getClock(tx);
    const members = await tx.query<{ house_id: string; human_id: string }>(`SELECT cm.house_id,h.current_human_id AS human_id FROM community_memberships cm JOIN houses h ON h.id=cm.house_id WHERE cm.community_id=$1 AND cm.status='ACTIVE' AND h.current_human_id IS NOT NULL`, [input.communityId]);
    await tx.query(`UPDATE communities SET status='DISBANDED',disbanded_at=CURRENT_TIMESTAMP,updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND status='ACTIVE'`, [input.communityId]); await tx.query(`UPDATE community_memberships SET status='REMOVED',left_at=CURRENT_TIMESTAMP,updated_at=CURRENT_TIMESTAMP WHERE community_id=$1 AND status='ACTIVE'`, [input.communityId]); await tx.query(`UPDATE community_membership_requests SET status='CANCELLED',decided_by_human_id=$1,decided_at=CURRENT_TIMESTAMP WHERE community_id=$2 AND status='PENDING'`, [input.humanId, input.communityId]);
    await createGameEvent(tx, { id: newId('EVENT'), category: 'INSTITUTION', eventType: 'COMMUNITY_DISBANDED', gameDay: time.gameDay, gameMinute: time.gameMinute, actorHouseId: input.houseId, actorHumanId: input.humanId, subjectType: 'COMMUNITY', subjectId: input.communityId, title: 'Community disbanded', correlationId: `community-disband:${input.communityId}` });
    for (const member of members.rows) await addNotification(tx, member.house_id, member.human_id, input.communityId, 'COMMUNITY_DISBANDED', 'Community disbanded', 'This community has been disbanded.', time.gameDay, time.gameMinute, `community-disband-notification:${input.communityId}:${member.house_id}`);
    return { ok: true, status: 'DISBANDED' };
  });
}
