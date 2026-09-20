import type { PostgresRepository } from './repository.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';
import { createGameEvent as writeGameEvent, type GameEventInput } from './game-events-postgres.ts';
import { createNotification } from './notifications-postgres.ts';
import { enqueueOutbox } from './outbox-postgres.ts';
import { earthError } from './errors.ts';

type CommunityRole = 'OWNER' | 'MODERATOR' | 'MEMBER';
type MembershipAction = 'join' | 'leave' | 'remove';
export type CommunityViewerPermissions = {
  membershipStatus: 'ACTIVE' | null;
  role: CommunityRole | null;
  requestStatus: string | null;
  requestId: string | null;
  canJoin: boolean;
  canLeave: boolean;
  canEdit: boolean;
  canManageMembers: boolean;
  canApproveRequests: boolean;
  canChangeRoles: boolean;
  canDisband: boolean;
  capabilities: CommunityCapabilityMatrix;
};

export type CommunityCapabilityMatrix = {
  canJoin: boolean;
  canLeave: boolean;
  canEdit: boolean;
  canManageMembers: boolean;
  canApproveRequests: boolean;
  canChangeRoles: boolean;
  canDisband: boolean;
  canTransferOwnership: boolean;
  canCancelRequest: boolean;
};

export type CommunitySummary = {
  id: string;
  name: string;
  description: string;
  visibility: 'PUBLIC';
  join_policy: 'OPEN' | 'REQUEST';
  status: 'ACTIVE' | 'DISBANDED';
  founder_house_id: string;
  founder_house_name: string | null;
  created_game_day: number;
  created_game_minute: number;
  created_at: string;
  updated_at: string;
  member_count: number;
  viewer: CommunityViewerPermissions;
};

export type CommunityMember = {
  house_id: string;
  house_name: string;
  current_human_id: string | null;
  current_human_name: string | null;
  role: CommunityRole;
  status: string;
  joined_game_day: number;
  joined_game_minute: number;
  joined_at: string;
  left_at: string | null;
};

export type CommunityMembershipRequest = {
  id: string;
  community_id: string;
  house_id: string;
  house_name: string;
  current_human_id: string | null;
  current_human_name: string | null;
  application_message: string;
  decision_note: string | null;
  status: string;
  requested_game_day: number;
  requested_game_minute: number;
  created_at: string;
  decided_at: string | null;
};

export type CommunityDetail = CommunitySummary & {
  members?: CommunityMember[];
  requests?: CommunityMembershipRequest[];
};

export type CommunityWorkspace = CommunitySummary & {
  pending_request_count: number;
  member_preview: CommunityMember[];
  member_next_cursor: string | null;
  request_next_cursor: string | null;
};

export type CommunityMemberRosterEntry = CommunityMember;
export type CommunityMembershipRequestDto = CommunityMembershipRequest;
type CommunityMembershipRequestRecord = CommunityMembershipRequest & {
  requested_by_human_id: string;
  decided_by_human_id: string | null;
};
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
  return readAuthoritativeGameTime(repo);
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

function withViewerState(row: Record<string, any>, houseId?: string): CommunitySummary {
  const membershipStatus = row.viewer_membership_status === 'ACTIVE' ? 'ACTIVE' : null;
  const role = membershipStatus ? row.viewer_role : null;
  const requestStatus = membershipStatus ? null : (row.viewer_request_status ?? null);
  const requestId = membershipStatus ? null : (row.viewer_request_id ?? null);
  const active = row.status === 'ACTIVE';
  const ownerCount = Number(row.active_owner_count ?? 0);
  const manager = active && (role === 'OWNER' || role === 'MODERATOR');
  const owner = active && role === 'OWNER';
  const capabilities: CommunityCapabilityMatrix = {
    canJoin: Boolean(houseId) && active && !membershipStatus && requestStatus !== 'PENDING',
    canLeave: Boolean(membershipStatus) && (!owner || ownerCount > 1),
    canEdit: manager,
    canManageMembers: manager,
    canApproveRequests: manager,
    canChangeRoles: owner,
    canDisband: owner,
    canTransferOwnership: owner,
    canCancelRequest: Boolean(houseId) && !membershipStatus && requestStatus === 'PENDING',
  };
  const { viewer_role: _viewerRole, viewer_membership_status: _viewerMembershipStatus, viewer_request_status: _viewerRequestStatus, viewer_request_id: _viewerRequestId, active_owner_count: _activeOwnerCount, ...community } = row;
  return {
    ...community,
    member_count: Number(row.member_count ?? 0),
    viewer: {
      membershipStatus,
      role,
      requestStatus,
      requestId,
      ...capabilities,
      capabilities,
    },
  } as CommunitySummary;
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

async function loadMembershipRequest(repo: PostgresRepository, where: string, values: unknown[], lock = false) {
  const result = await repo.query<CommunityMembershipRequestRecord>(`SELECT r.id,r.community_id,r.house_id,h.house_name,h.current_human_id,
      hu.display_name AS current_human_name,r.message AS application_message,r.decision_note,r.status,
      r.requested_by_human_id,r.decided_by_human_id,r.requested_game_day,r.requested_game_minute,
      r.created_at,r.decided_at
    FROM community_membership_requests r
    JOIN houses h ON h.id=r.house_id
    LEFT JOIN humans hu ON hu.id=h.current_human_id
    WHERE ${where} ${lock ? 'FOR UPDATE' : ''}`, values);
  return result.rows[0];
}

async function loadCommunityMember(repo: PostgresRepository, communityId: string, houseId: string): Promise<CommunityMember | null> {
  const result = await repo.query<CommunityMember>(`SELECT cm.house_id,h.house_name,h.current_human_id,
      hu.display_name AS current_human_name,cm.role,cm.status,cm.joined_game_day,
      cm.joined_game_minute,cm.joined_at,cm.left_at
    FROM community_memberships cm
    JOIN houses h ON h.id=cm.house_id
    LEFT JOIN humans hu ON hu.id=h.current_human_id
    WHERE cm.community_id=$1 AND cm.house_id=$2`, [communityId, houseId]);
  return result.rows[0] ?? null;
}

export async function listCommunities(repo: PostgresRepository, houseId?: string, membership: 'mine' | undefined = undefined) {
  const result = await repo.query(`
    SELECT c.*,
      (SELECT COUNT(*)::int FROM community_memberships all_cm WHERE all_cm.community_id=c.id AND all_cm.status='ACTIVE') AS member_count,
      (SELECT COUNT(*)::int FROM community_memberships owners WHERE owners.community_id=c.id AND owners.status='ACTIVE' AND owners.role='OWNER') AS active_owner_count,
      (SELECT h.house_name FROM houses h WHERE h.id=c.founder_house_id) AS founder_house_name,
      cm.role AS viewer_role,
      cm.status AS viewer_membership_status,
      pending.id AS viewer_request_id,
      pending.status AS viewer_request_status
    FROM communities c
    LEFT JOIN community_memberships cm ON cm.community_id=c.id AND cm.house_id=$1
    LEFT JOIN LATERAL (
      SELECT r.id, r.status
      FROM community_membership_requests r
      WHERE r.community_id=c.id AND r.house_id=$1
      ORDER BY r.created_at DESC
      LIMIT 1
    ) pending ON true
    WHERE c.status='ACTIVE' AND c.visibility='PUBLIC' ${membership === 'mine' ? "AND cm.status='ACTIVE'" : ''}
    ORDER BY c.created_at DESC`, [houseId ?? null]);
  return { ok: true, communities: result.rows.map((row) => withViewerState(row, houseId)) };
}

function encodeCommunityCursor(createdAt: string, id: string): string {
  return btoa(JSON.stringify({ createdAt, id }));
}

function decodeCommunityCursor(value: string | null): { createdAt: string; id: string } | null {
  if (!value) return null;
  try {
    const parsed = JSON.parse(atob(value)) as { createdAt?: unknown; id?: unknown };
    if (typeof parsed.createdAt !== 'string' || typeof parsed.id !== 'string') return null;
    return { createdAt: parsed.createdAt, id: parsed.id };
  } catch {
    return null;
  }
}

export async function listCommunityDirectory(
  repo: PostgresRepository,
  input: {
    houseId: string;
    limit?: number;
    cursor?: string | null;
    search?: string | null;
    joinPolicy?: 'OPEN' | 'REQUEST' | null;
    membership?: 'mine' | null;
    viewerStatus?: 'PENDING' | null;
  },
) {
  const requestedLimit = Number(input.limit ?? 20);
  if (!Number.isFinite(requestedLimit)) {
    throw earthError('VALIDATION_ERROR', 'Community directory limit must be a number.', { field: 'limit' });
  }
  const limit = Math.min(50, Math.max(1, Math.trunc(requestedLimit)));
  const cursor = decodeCommunityCursor(input.cursor ?? null);
  if (input.cursor && !cursor) throw earthError('VALIDATION_ERROR', 'Invalid community directory cursor.', { field: 'cursor' });

  const params: unknown[] = [input.houseId];
  const conditions = ["c.status='ACTIVE'", "c.visibility='PUBLIC'"];
  const bind = (value: unknown) => {
    params.push(value);
    return `$${params.length}`;
  };
  if (input.search?.trim()) {
    const term = `%${input.search.trim().replace(/[%_]/g, '\\$&')}%`;
    conditions.push(`(c.name ILIKE ${bind(term)} ESCAPE '\\' OR c.description ILIKE ${bind(term)} ESCAPE '\\')`);
  }
  if (input.joinPolicy) conditions.push(`c.join_policy=${bind(input.joinPolicy)}`);
  if (input.membership === 'mine') conditions.push("cm.status='ACTIVE'");
  if (input.viewerStatus === 'PENDING') conditions.push("pending.status='PENDING'");
  if (cursor) {
    conditions.push(`(c.created_at, c.id) < (${bind(cursor.createdAt)}, ${bind(cursor.id)})`);
  }
  const from = `
    FROM communities c
    LEFT JOIN community_memberships cm ON cm.community_id=c.id AND cm.house_id=$1
    LEFT JOIN LATERAL (
      SELECT r.id, r.status
      FROM community_membership_requests r
      WHERE r.community_id=c.id AND r.house_id=$1
      ORDER BY r.created_at DESC
      LIMIT 1
    ) pending ON true
    WHERE ${conditions.join(' AND ')}`;
  const select = `SELECT c.*,
      (SELECT COUNT(*)::int FROM community_memberships all_cm WHERE all_cm.community_id=c.id AND all_cm.status='ACTIVE') AS member_count,
      (SELECT COUNT(*)::int FROM community_memberships owners WHERE owners.community_id=c.id AND owners.status='ACTIVE' AND owners.role='OWNER') AS active_owner_count,
      (SELECT h.house_name FROM houses h WHERE h.id=c.founder_house_id) AS founder_house_name,
      cm.role AS viewer_role, cm.status AS viewer_membership_status,
      pending.id AS viewer_request_id, pending.status AS viewer_request_status ${from}
      ORDER BY c.created_at DESC, c.id DESC LIMIT ${limit + 1}`;
  const countParams = params.slice(0, cursor ? -2 : undefined);
  const countConditions = cursor ? conditions.slice(0, -1) : conditions;
  const countFrom = `
    FROM communities c
    LEFT JOIN community_memberships cm ON cm.community_id=c.id AND cm.house_id=$1
    LEFT JOIN LATERAL (
      SELECT r.id, r.status
      FROM community_membership_requests r
      WHERE r.community_id=c.id AND r.house_id=$1
      ORDER BY r.created_at DESC
      LIMIT 1
    ) pending ON true
    WHERE ${countConditions.join(' AND ')}`;
  const [rows, count] = await Promise.all([
    repo.query(select, params),
    repo.query<{ count: string }>(`SELECT COUNT(*)::text AS count ${countFrom}`, countParams),
  ]);
  const hasMore = rows.rows.length > limit;
  const page = hasMore ? rows.rows.slice(0, limit) : rows.rows;
  const last = page[page.length - 1] as Record<string, unknown> | undefined;
  return {
    ok: true,
    communities: page.map((row) => withViewerState(row, input.houseId)),
    totalCount: Number(count.rows[0]?.count ?? 0),
    hasMore,
    nextCursor: hasMore && last ? encodeCommunityCursor(String(last.created_at), String(last.id)) : null,
  };
}

export async function getCommunity(repo: PostgresRepository, communityId: string, houseId: string) {
  const result = await repo.query(`
    SELECT c.*,
      (SELECT COUNT(*)::int FROM community_memberships all_cm WHERE all_cm.community_id=c.id AND all_cm.status='ACTIVE') AS member_count,
      (SELECT COUNT(*)::int FROM community_memberships owners WHERE owners.community_id=c.id AND owners.status='ACTIVE' AND owners.role='OWNER') AS active_owner_count,
      (SELECT h.house_name FROM houses h WHERE h.id=c.founder_house_id) AS founder_house_name,
      cm.role AS viewer_role,
      cm.status AS viewer_membership_status,
      pending.id AS viewer_request_id,
      pending.status AS viewer_request_status
    FROM communities c
    LEFT JOIN community_memberships cm ON cm.community_id=c.id AND cm.house_id=$2
    LEFT JOIN LATERAL (
      SELECT r.id, r.status
      FROM community_membership_requests r
      WHERE r.community_id=c.id AND r.house_id=$2
      ORDER BY r.created_at DESC
      LIMIT 1
    ) pending ON true
    WHERE c.id=$1 AND c.visibility='PUBLIC'`, [communityId, houseId]);
  if (!result.rows[0]) throw earthError('NOT_FOUND', 'Community not found.');
  const community: CommunityDetail = withViewerState(result.rows[0], houseId);
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
    if (visibility !== 'PUBLIC' || !['OPEN', 'REQUEST'].includes(joinPolicy)) throw earthError('VALIDATION_ERROR', 'Communities are public; choose OPEN or REQUEST admission.');
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
    if (input.visibility !== undefined) { if (input.visibility !== 'PUBLIC') throw earthError('VALIDATION_ERROR', 'Communities are public; private visibility is not supported.', { field: 'visibility' }); add('visibility', 'PUBLIC'); }
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
    await assertActor(tx, input.houseId, input.humanId); const c = await loadCommunity(tx, input.communityId, true); if (c.visibility !== 'PUBLIC') throw earthError('NOT_FOUND', 'Community not found.'); if (c.status !== 'ACTIVE') throw earthError('COMMUNITY_DISBANDED', 'Community is disbanded.');
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
      return { ok: true, status: 'REMOVED', member: await loadCommunityMember(tx, input.communityId, input.targetHouseId) };
    }
    if (input.correlationId) {
      const prior = await tx.query<{ event_type: string }>(
        `SELECT event_type FROM game_events
          WHERE (correlation_id=$1 OR correlation_id=$2)
            AND event_type IN ('COMMUNITY_JOINED','COMMUNITY_JOIN_REQUESTED','COMMUNITY_LEFT')
          ORDER BY created_at DESC LIMIT 1`,
        [input.correlationId, `community-request-event:${input.correlationId}`],
      );
      if (prior.rows[0]) {
        const status = prior.rows[0].event_type === 'COMMUNITY_JOINED'
          ? 'ACTIVE'
          : prior.rows[0].event_type === 'COMMUNITY_LEFT'
            ? 'LEFT'
            : 'PENDING';
        return { ok: true, alreadyProcessed: true, status };
      }
    }
    const time = await getClock(tx); const existing = await tx.query<{ role: CommunityRole; status: string }>(`SELECT role,status FROM community_memberships WHERE community_id=$1 AND house_id=$2 FOR UPDATE`, [input.communityId, input.houseId]);
    if (input.action === 'leave') {
      if (!existing.rows[0] || existing.rows[0].status !== 'ACTIVE') throw earthError('NOT_FOUND', 'House is not an active member.');
      if (existing.rows[0].role === 'OWNER') throw earthError('COMMUNITY_LAST_OWNER', 'The owner must transfer ownership or disband the Community before leaving.');
      await tx.query(`UPDATE community_memberships SET status='LEFT',left_at=CURRENT_TIMESTAMP,updated_at=CURRENT_TIMESTAMP WHERE community_id=$1 AND house_id=$2`, [input.communityId, input.houseId]);
      await createGameEvent(tx, { id: newId('EVENT'), category: 'AFFILIATION', eventType: 'COMMUNITY_LEFT', gameDay: time.gameDay, gameMinute: time.gameMinute, actorHouseId: input.houseId, actorHumanId: input.humanId, subjectType: 'COMMUNITY', subjectId: input.communityId, title: 'House left community', correlationId: input.correlationId ?? `community-leave:${input.communityId}:${input.houseId}:${time.gameDay}` });
      return { ok: true, status: 'LEFT', member: await loadCommunityMember(tx, input.communityId, input.houseId) };
    }
    if (existing.rows[0]?.status === 'ACTIVE') throw earthError('COMMUNITY_ALREADY_MEMBER', 'House is already an active member.');
    if (c.join_policy === 'OPEN') {
      await tx.query(`INSERT INTO community_memberships (community_id,house_id,role,status,joined_by_human_id,joined_game_day,joined_game_minute,left_at) VALUES ($1,$2,'MEMBER','ACTIVE',$3,$4,$5,NULL) ON CONFLICT (community_id,house_id) DO UPDATE SET role='MEMBER',status='ACTIVE',joined_by_human_id=EXCLUDED.joined_by_human_id,joined_game_day=EXCLUDED.joined_game_day,joined_game_minute=EXCLUDED.joined_game_minute,left_at=NULL,updated_at=CURRENT_TIMESTAMP`, [input.communityId, input.houseId, input.humanId, time.gameDay, time.gameMinute]);
      await createGameEvent(tx, { id: newId('EVENT'), category: 'AFFILIATION', eventType: 'COMMUNITY_JOINED', gameDay: time.gameDay, gameMinute: time.gameMinute, actorHouseId: input.houseId, actorHumanId: input.humanId, subjectType: 'COMMUNITY', subjectId: input.communityId, title: 'House joined community', correlationId: input.correlationId ?? `community-join:${input.communityId}:${input.houseId}:${time.gameDay}` });
      return { ok: true, status: 'ACTIVE', member: await loadCommunityMember(tx, input.communityId, input.houseId) };
    }
    const correlationId = input.correlationId ?? `community-request:${input.communityId}:${input.houseId}:${time.gameDay}`;
    const pending = await tx.query<{ id: string }>(`SELECT id FROM community_membership_requests WHERE community_id=$1 AND house_id=$2 AND status='PENDING' FOR UPDATE`, [input.communityId, input.houseId]);
    if (pending.rows[0]) return { ok: true, alreadyProcessed: true, status: 'PENDING', request: await loadMembershipRequest(tx, 'r.id=$1', [pending.rows[0].id]) };
    const requestId = newId('REQUEST'); await tx.query(`INSERT INTO community_membership_requests (id,community_id,house_id,message,requested_by_human_id,correlation_id,requested_game_day,requested_game_minute) VALUES ($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT (correlation_id) DO NOTHING`, [requestId, input.communityId, input.houseId, input.applicationMessage?.trim().slice(0, 2000) ?? '', input.humanId, correlationId, time.gameDay, time.gameMinute]);
    await createGameEvent(tx, { id: newId('EVENT'), category: 'AFFILIATION', eventType: 'COMMUNITY_JOIN_REQUESTED', gameDay: time.gameDay, gameMinute: time.gameMinute, actorHouseId: input.houseId, actorHumanId: input.humanId, subjectType: 'COMMUNITY', subjectId: input.communityId, title: 'Community membership requested', correlationId: `community-request-event:${correlationId}` });
    await notifyManagers(tx, input.communityId, c.name, time.gameDay, time.gameMinute, `community-request-notification:${correlationId}`);
    return { ok: true, status: 'PENDING', request: await loadMembershipRequest(tx, 'r.correlation_id=$1', [correlationId]) };
  });
}

export async function listCommunityMembers(repo: PostgresRepository, communityId: string, houseId?: string) {
  const c = await loadCommunity(repo, communityId); if (c.visibility !== 'PUBLIC') throw earthError('NOT_FOUND', 'Community not found.');
  const result = await repo.query<CommunityMember>(`SELECT cm.house_id,h.house_name,h.current_human_id,hu.display_name AS current_human_name,
      cm.role,cm.status,cm.joined_game_day,cm.joined_game_minute,cm.joined_at,cm.left_at
    FROM community_memberships cm
    JOIN houses h ON h.id=cm.house_id
    LEFT JOIN humans hu ON hu.id=h.current_human_id
    WHERE cm.community_id=$1 ORDER BY cm.joined_at`, [communityId]);
  return { ok: true, members: result.rows };
}

export async function listCommunityMembershipRequests(repo: PostgresRepository, communityId: string, houseId: string) {
  const community = await loadCommunity(repo, communityId);
  if (community.visibility !== 'PUBLIC') throw earthError('NOT_FOUND', 'Community not found.');
  requireManager(await getRole(repo, communityId, houseId));
  const result = await repo.query<CommunityMembershipRequest>(`SELECT r.id,r.community_id,r.house_id,h.house_name,h.current_human_id,
      hu.display_name AS current_human_name,r.message AS application_message,r.decision_note,r.status,
      r.requested_game_day,r.requested_game_minute,r.created_at,r.decided_at
    FROM community_membership_requests r
    JOIN houses h ON h.id=r.house_id
    LEFT JOIN humans hu ON hu.id=h.current_human_id
    WHERE r.community_id=$1 ORDER BY r.created_at DESC`, [communityId]);
  return { ok: true, requests: result.rows };
}

export async function getCommunityWorkspace(repo: PostgresRepository, communityId: string, houseId: string) {
  const communityResult = await getCommunity(repo, communityId, houseId);
  const community = communityResult.community;
  const [members, requests] = await Promise.all([
    listCommunityMembersPage(repo, { communityId, limit: 10 }),
    community.viewer.capabilities.canApproveRequests
      ? listCommunityMembershipRequestsPage(repo, { communityId, houseId, limit: 1 })
      : Promise.resolve({ requests: [], totalCount: 0, hasMore: false, nextCursor: null }),
  ]);
  return {
    ok: true,
    workspace: {
      ...community,
      pending_request_count: requests.totalCount,
      member_preview: members.members,
      member_next_cursor: members.nextCursor,
      request_next_cursor: requests.nextCursor,
    } satisfies CommunityWorkspace,
  };
}

function decodePageCursor(value: string | null): Record<string, string> | null {
  if (!value) return null;
  try {
    const parsed = JSON.parse(atob(value));
    return parsed && typeof parsed === 'object' ? parsed as Record<string, string> : null;
  } catch { return null; }
}

function encodePageCursor(value: Record<string, string>): string {
  return btoa(JSON.stringify(value));
}

export async function listCommunityMembersPage(repo: PostgresRepository, input: { communityId: string; limit?: number; cursor?: string | null; search?: string | null }) {
  const limit = Math.min(50, Math.max(1, Math.trunc(Number(input.limit ?? 25))));
  const cursor = decodePageCursor(input.cursor ?? null);
  const params: unknown[] = [input.communityId];
  const conditions = ["cm.community_id=$1", "cm.status='ACTIVE'"];
  const bind = (value: unknown) => { params.push(value); return `$${params.length}`; };
  if (input.search?.trim()) conditions.push(`(h.house_name ILIKE ${bind(`%${input.search.trim()}%`)} OR hu.display_name ILIKE ${bind(`%${input.search.trim()}%`)})`);
  if (cursor?.joinedAt && cursor.houseId) conditions.push(`(cm.joined_at,cm.house_id) > (${bind(cursor.joinedAt)},${bind(cursor.houseId)})`);
  const from = `FROM community_memberships cm JOIN houses h ON h.id=cm.house_id LEFT JOIN humans hu ON hu.id=h.current_human_id WHERE ${conditions.join(' AND ')}`;
  const [rows, count] = await Promise.all([
    repo.query<CommunityMember>(`SELECT cm.house_id,h.house_name,h.current_human_id,hu.display_name AS current_human_name,cm.role,cm.status,cm.joined_game_day,cm.joined_game_minute,cm.joined_at,cm.left_at ${from} ORDER BY cm.joined_at,cm.house_id LIMIT ${limit + 1}`, params),
    repo.query<{ count: string }>(`SELECT COUNT(*)::text AS count ${from}`, params.slice(0, input.search?.trim() ? 3 : 1)),
  ]);
  const hasMore = rows.rows.length > limit;
  const members = hasMore ? rows.rows.slice(0, limit) : rows.rows;
  const last = members[members.length - 1];
  return { members, totalCount: Number(count.rows[0]?.count ?? 0), hasMore, nextCursor: hasMore && last ? encodePageCursor({ joinedAt: String(last.joined_at), houseId: String(last.house_id) }) : null };
}

export async function listCommunityMembershipRequestsPage(repo: PostgresRepository, input: { communityId: string; houseId: string; limit?: number; cursor?: string | null; search?: string | null }) {
  requireManager(await getRole(repo, input.communityId, input.houseId));
  const limit = Math.min(50, Math.max(1, Math.trunc(Number(input.limit ?? 25))));
  const cursor = decodePageCursor(input.cursor ?? null);
  const params: unknown[] = [input.communityId];
  const conditions = ['r.community_id=$1'];
  const bind = (value: unknown) => { params.push(value); return `$${params.length}`; };
  if (input.search?.trim()) conditions.push(`(h.house_name ILIKE ${bind(`%${input.search.trim()}%`)} OR hu.display_name ILIKE ${bind(`%${input.search.trim()}%`)})`);
  if (cursor?.createdAt && cursor.id) conditions.push(`(r.created_at,r.id) < (${bind(cursor.createdAt)},${bind(cursor.id)})`);
  const from = `FROM community_membership_requests r JOIN houses h ON h.id=r.house_id LEFT JOIN humans hu ON hu.id=h.current_human_id WHERE ${conditions.join(' AND ')}`;
  const [rows, count] = await Promise.all([
    repo.query<CommunityMembershipRequest>(`SELECT r.id,r.community_id,r.house_id,h.house_name,h.current_human_id,hu.display_name AS current_human_name,r.message AS application_message,r.decision_note,r.status,r.requested_game_day,r.requested_game_minute,r.created_at,r.decided_at ${from} ORDER BY r.created_at DESC,r.id DESC LIMIT ${limit + 1}`, params),
    repo.query<{ count: string }>(`SELECT COUNT(*)::text AS count ${from}`, params.slice(0, input.search?.trim() ? 3 : 1)),
  ]);
  const hasMore = rows.rows.length > limit;
  const requests = hasMore ? rows.rows.slice(0, limit) : rows.rows;
  const last = requests[requests.length - 1];
  return { requests, totalCount: Number(count.rows[0]?.count ?? 0), hasMore, nextCursor: hasMore && last ? encodePageCursor({ createdAt: String(last.created_at), id: String(last.id) }) : null };
}

export async function decideCommunityMembershipRequest(repo: PostgresRepository, input: { communityId: string; requestId: string; actorHouseId: string; actorHumanId: string; action: 'approve' | 'reject'; rejectionReason?: string }) {
  return repo.transaction(async (tx) => {
    await assertActor(tx, input.actorHouseId, input.actorHumanId); const community = await loadCommunity(tx, input.communityId, true); if (community.visibility !== 'PUBLIC') throw earthError('NOT_FOUND', 'Community not found.'); requireManager(await getRole(tx, input.communityId, input.actorHouseId, true));
    const request = await loadMembershipRequest(tx, 'r.id=$1 AND r.community_id=$2', [input.requestId, input.communityId], true); if (!request) throw earthError('NOT_FOUND', 'Membership request not found.'); if (request.status !== 'PENDING') throw earthError('CONFLICT', 'Membership request is already decided.');
    const time = await getClock(tx);
    if (input.action === 'approve') { await tx.query(`INSERT INTO community_memberships (community_id,house_id,role,status,joined_by_human_id,joined_game_day,joined_game_minute,left_at) VALUES ($1,$2,'MEMBER','ACTIVE',$3,$4,$5,NULL) ON CONFLICT (community_id,house_id) DO UPDATE SET role='MEMBER',status='ACTIVE',joined_by_human_id=EXCLUDED.joined_by_human_id,joined_game_day=EXCLUDED.joined_game_day,joined_game_minute=EXCLUDED.joined_game_minute,left_at=NULL,updated_at=CURRENT_TIMESTAMP`, [input.communityId, request.house_id, request.requested_by_human_id, time.gameDay, time.gameMinute]); await tx.query(`UPDATE community_membership_requests SET status='APPROVED',decided_by_human_id=$1,decided_at=CURRENT_TIMESTAMP WHERE id=$2`, [input.actorHumanId, input.requestId]); }
    else await tx.query(`UPDATE community_membership_requests SET status='REJECTED',decision_note=$1,decided_by_human_id=$2,decided_at=CURRENT_TIMESTAMP WHERE id=$3`, [input.rejectionReason?.trim().slice(0, 2000) || null, input.actorHumanId, input.requestId]);
    await createGameEvent(tx, { id: newId('EVENT'), category: 'AFFILIATION', eventType: input.action === 'approve' ? 'COMMUNITY_JOIN_APPROVED' : 'COMMUNITY_JOIN_REJECTED', gameDay: time.gameDay, gameMinute: time.gameMinute, actorHouseId: input.actorHouseId, actorHumanId: input.actorHumanId, subjectType: 'COMMUNITY', subjectId: input.communityId, title: input.action === 'approve' ? 'House joined community' : 'Community request rejected', details: { affectedHouseId: request.house_id }, correlationId: `community-request-decision:${input.requestId}:${input.action}` });
    const applicant = (await tx.query<{ human_id: string | null }>(`SELECT current_human_id AS human_id FROM houses WHERE id=$1`, [request.house_id])).rows[0]?.human_id;
    if (applicant) await addNotification(tx, request.house_id, applicant, input.communityId, 'COMMUNITY_REQUEST_DECIDED', input.action === 'approve' ? 'Community request approved' : 'Community request rejected', input.action === 'approve' ? 'Your House joined the community.' : 'Your community request was rejected.', time.gameDay, time.gameMinute, `community-request-notification:${input.requestId}:${input.action}`);
    return {
      ok: true,
      status: input.action === 'approve' ? 'APPROVED' : 'REJECTED',
      request: await loadMembershipRequest(tx, 'r.id=$1', [input.requestId]),
      member: input.action === 'approve'
        ? await loadCommunityMember(tx, input.communityId, request.house_id)
        : null,
    };
  });
}

export async function cancelCommunityMembershipRequest(repo: PostgresRepository, input: { communityId: string; requestId: string; houseId: string; humanId: string }) {
  return repo.transaction(async (tx) => {
    await assertActor(tx, input.houseId, input.humanId);
    const community = await loadCommunity(tx, input.communityId, true);
    if (community.visibility !== 'PUBLIC') throw earthError('NOT_FOUND', 'Community not found.');
    const request = await loadMembershipRequest(tx, 'r.id=$1 AND r.community_id=$2', [input.requestId, input.communityId], true);
    if (!request || request.house_id !== input.houseId) throw earthError('NOT_FOUND', 'Membership request not found.');
    if (request.status !== 'PENDING') throw earthError('CONFLICT', 'Only pending applications can be cancelled.');
    const time = await getClock(tx);
    await tx.query(`UPDATE community_membership_requests SET status='CANCELLED',decided_at=CURRENT_TIMESTAMP WHERE id=$1`, [input.requestId]);
    await createGameEvent(tx, { id: newId('EVENT'), category: 'AFFILIATION', eventType: 'COMMUNITY_JOIN_CANCELLED', gameDay: time.gameDay, gameMinute: time.gameMinute, actorHouseId: input.houseId, actorHumanId: input.humanId, subjectType: 'COMMUNITY', subjectId: input.communityId, title: 'Community application cancelled', details: { requestId: input.requestId, houseId: input.houseId }, correlationId: `community-request-cancel:${input.requestId}` });
    return { ok: true, status: 'CANCELLED' };
  });
}

export async function setCommunityMemberRole(repo: PostgresRepository, input: { communityId: string; actorHouseId: string; actorHumanId: string; targetHouseId: string; role: CommunityRole }) {
  return repo.transaction(async (tx) => {
    await assertActor(tx, input.actorHouseId, input.actorHumanId); const community = await loadCommunity(tx, input.communityId, true); if (community.visibility !== 'PUBLIC') throw earthError('NOT_FOUND', 'Community not found.'); const actorRole = await getRole(tx, input.communityId, input.actorHouseId, true); if (actorRole !== 'OWNER') throw earthError('FORBIDDEN', 'Only the Community owner can change roles.');
    const target = (await tx.query<{ role: CommunityRole; status: string }>(`SELECT role,status FROM community_memberships WHERE community_id=$1 AND house_id=$2 FOR UPDATE`, [input.communityId, input.targetHouseId])).rows[0]; if (!target || target.status !== 'ACTIVE') throw earthError('NOT_FOUND', 'Target House is not an active member.'); if (!['MODERATOR', 'MEMBER'].includes(input.role)) throw earthError('VALIDATION_ERROR', 'Use ownership transfer to change the owner.', { field: 'role' });
    if (target.role === 'OWNER') throw earthError('COMMUNITY_LAST_OWNER', 'Transfer ownership before changing the owner role.');
    await tx.query(`UPDATE community_memberships SET role=$1,updated_at=CURRENT_TIMESTAMP WHERE community_id=$2 AND house_id=$3`, [input.role, input.communityId, input.targetHouseId]);
    const time = await getClock(tx);
    await createGameEvent(tx, { id: newId('EVENT'), category: 'INSTITUTION', eventType: 'COMMUNITY_ROLE_CHANGED', gameDay: time.gameDay, gameMinute: time.gameMinute, actorHouseId: input.actorHouseId, actorHumanId: input.actorHumanId, subjectType: 'COMMUNITY', subjectId: input.communityId, title: 'Community role changed', details: { targetHouseId: input.targetHouseId, role: input.role }, correlationId: `community-role:${input.communityId}:${input.targetHouseId}:${time.gameDay}:${input.role}` });
    const targetHuman = (await tx.query<{ human_id: string }>(`SELECT current_human_id AS human_id FROM houses WHERE id=$1`, [input.targetHouseId])).rows[0]?.human_id;
    if (targetHuman) await addNotification(tx, input.targetHouseId, targetHuman, input.communityId, 'COMMUNITY_ROLE_CHANGED', 'Community role changed', `Your role is now ${input.role}.`, time.gameDay, time.gameMinute, `community-role-notification:${input.communityId}:${input.targetHouseId}:${time.gameDay}:${input.role}`);
    return { ok: true, role: input.role, member: await loadCommunityMember(tx, input.communityId, input.targetHouseId) };
  });
}

export async function transferCommunityOwnership(repo: PostgresRepository, input: { communityId: string; actorHouseId: string; actorHumanId: string; targetHouseId: string }) {
  return repo.transaction(async (tx) => {
    if (input.actorHouseId === input.targetHouseId) throw earthError('VALIDATION_ERROR', 'A different member House is required.', { field: 'targetHouseId' });
    await assertActor(tx, input.actorHouseId, input.actorHumanId);
    const community = await loadCommunity(tx, input.communityId, true);
    if (community.visibility !== 'PUBLIC') throw earthError('NOT_FOUND', 'Community not found.');
    const members = await tx.query<{ house_id: string; role: CommunityRole; status: string }>(`SELECT house_id,role,status FROM community_memberships WHERE community_id=$1 AND house_id IN ($2,$3) ORDER BY house_id FOR UPDATE`, [input.communityId, input.actorHouseId, input.targetHouseId]);
    const actor = members.rows.find((row) => row.house_id === input.actorHouseId);
    const target = members.rows.find((row) => row.house_id === input.targetHouseId);
    if (!actor || actor.status !== 'ACTIVE' || actor.role !== 'OWNER') throw earthError('FORBIDDEN', 'Only the current Community owner can transfer ownership.');
    if (!target || target.status !== 'ACTIVE') throw earthError('NOT_FOUND', 'Target House is not an active member.');
    const time = await getClock(tx);
    await tx.query(`UPDATE community_memberships SET role=CASE WHEN house_id=$1 THEN 'MODERATOR' ELSE 'OWNER' END,updated_at=CURRENT_TIMESTAMP WHERE community_id=$3 AND house_id IN ($1,$2)`, [input.actorHouseId, input.targetHouseId, input.communityId]);
    await createGameEvent(tx, { id: newId('EVENT'), category: 'INSTITUTION', eventType: 'COMMUNITY_OWNERSHIP_TRANSFERRED', gameDay: time.gameDay, gameMinute: time.gameMinute, actorHouseId: input.actorHouseId, actorHumanId: input.actorHumanId, subjectType: 'COMMUNITY', subjectId: input.communityId, title: 'Community ownership transferred', details: { previousOwnerHouseId: input.actorHouseId, newOwnerHouseId: input.targetHouseId }, correlationId: `community-ownership-transfer:${input.communityId}:${input.targetHouseId}:${time.gameDay}` });
    const targetHuman = (await tx.query<{ human_id: string }>(`SELECT current_human_id AS human_id FROM houses WHERE id=$1`, [input.targetHouseId])).rows[0]?.human_id;
    if (targetHuman) await addNotification(tx, input.targetHouseId, targetHuman, input.communityId, 'COMMUNITY_OWNERSHIP_TRANSFERRED', 'Community ownership transferred', 'Your House is now the owner of this community.', time.gameDay, time.gameMinute, `community-ownership-notification:${input.communityId}:${input.targetHouseId}:${time.gameDay}`);
    return {
      ok: true,
      status: 'TRANSFERRED',
      ownerHouseId: input.targetHouseId,
      members: [
        await loadCommunityMember(tx, input.communityId, input.actorHouseId),
        await loadCommunityMember(tx, input.communityId, input.targetHouseId),
      ].filter((member): member is CommunityMember => member !== null),
    };
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
