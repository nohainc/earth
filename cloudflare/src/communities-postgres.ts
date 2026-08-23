import type { PostgresRepository } from './repository.ts';
import { transferCredits } from './financial-postgres.ts';
import { centsToMoney, moneyToCents } from './money.ts';

const MAX_NAME_LENGTH = 80;
const MAX_DESC_LENGTH = 500;

function requireName(name: string): string {
  const normalized = name.trim();
  if (normalized.length < 3 || normalized.length > MAX_NAME_LENGTH) {
    throw new Error('Community name must be 3–80 characters');
  }
  return normalized;
}

function sanitizeDescription(desc?: string): string {
  return (desc ?? '').trim().slice(0, MAX_DESC_LENGTH);
}

async function currentDay(repository: PostgresRepository): Promise<number> {
  const result = await repository.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
  return Number(result.rows[0]?.game_day ?? 0);
}

export async function listCommunities(repository: PostgresRepository): Promise<Record<string, unknown>> {
  const result = await repository.query(`
    SELECT 
      c.id, 
      c.name, 
      COALESCE(c.description, '') AS description, 
      c.founder_id, 
      COALESCE(h.display_name, 'Citizen') AS founder_name, 
      c.status, 
      COALESCE(c.admission_policy, 'open') AS admission_policy, 
      c.shared_credits,
      (SELECT COUNT(*)::integer FROM community_members cm WHERE cm.community_id = c.id) AS member_count
    FROM communities c
    LEFT JOIN humans h ON h.id = c.founder_id
    ORDER BY c.name
  `);
  return { communities: result.rows };
}

export async function createCommunity(
  repository: PostgresRepository,
  input: {
    founderId: string;
    name: string;
    description?: string;
    admissionPolicy?: 'open' | 'approval';
    correlationId: string;
  },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const name = requireName(input.name);
    const description = sanitizeDescription(input.description);
    const admissionPolicy = input.admissionPolicy === 'approval' ? 'approval' : 'open';

    const prior = await tx.query<{ institution_id: string }>(
      "SELECT institution_id FROM membership_events WHERE id = $1 AND human_id = $2 AND institution_type = 'COMMUNITY' AND reason = 'community_formation'",
      [input.correlationId, input.founderId],
    );
    if (prior.rows[0]) {
      return {
        ok: true,
        alreadyProcessed: true,
        community: (await tx.query('SELECT * FROM communities WHERE id = $1', [prior.rows[0].institution_id])).rows[0] ?? null,
        correlationId: input.correlationId,
      };
    }
    const founder = await tx.query<{ id: string }>("SELECT id FROM humans WHERE id = $1 AND life_status = 'active'", [input.founderId]);
    if (!founder.rows[0]) throw new Error('Founder not found');
    const conflict = await tx.query('SELECT id FROM communities WHERE lower(name) = lower($1)', [name]);
    if (conflict.rows[0]) throw new Error('Community name already exists');
    const day = await currentDay(tx);
    const communityId = `COMM-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    await tx.query(
      'INSERT INTO communities (id, name, description, admission_policy, founder_id, shared_credits) VALUES ($1,$2,$3,$4,$5,0)',
      [communityId, name, description, admissionPolicy, input.founderId],
    );
    await tx.query("INSERT INTO account_balances (account_id, owner_id, balance, currency) VALUES ($1, $2, 0, 'CREDIT')", [`account-community-${communityId}`, communityId]);
    await tx.query("INSERT INTO community_members (community_id, human_id, role, joined_game_day) VALUES ($1,$2,'founder',$3)", [communityId, input.founderId, day]);
    await tx.query("INSERT INTO membership_events (id, human_id, institution_type, institution_id, action, game_day, reason) VALUES ($1,$2,'COMMUNITY',$3,'joined',$4,'community_formation')", [input.correlationId, input.founderId, communityId, day]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [
      `COMMUNITY-FOUNDED-${input.founderId}-${communityId}`, input.founderId, 'community', 'Community founded', `You founded community ${communityId}.`, communityId,
    ]);
    return { ok: true, community: (await tx.query('SELECT * FROM communities WHERE id = $1', [communityId])).rows[0], correlationId: input.correlationId };
  });
}

export async function updateCommunity(
  repository: PostgresRepository,
  input: {
    communityId: string;
    humanId: string;
    description?: string;
    admissionPolicy?: 'open' | 'approval';
  },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const community = await tx.query<{ id: string; founder_id: string }>('SELECT id, founder_id FROM communities WHERE id = $1', [input.communityId]);
    if (!community.rows[0]) throw new Error('Community not found');

    const member = await tx.query<{ role: string }>('SELECT role FROM community_members WHERE community_id = $1 AND human_id = $2', [input.communityId, input.humanId]);
    const isFounderOrAdmin = community.rows[0].founder_id === input.humanId || member.rows[0]?.role === 'founder' || member.rows[0]?.role === 'admin';
    if (!isFounderOrAdmin) throw new Error('Only community founder or administrators can update settings');

    if (input.description !== undefined) {
      await tx.query('UPDATE communities SET description = $1 WHERE id = $2', [sanitizeDescription(input.description), input.communityId]);
    }
    if (input.admissionPolicy !== undefined) {
      const policy = input.admissionPolicy === 'approval' ? 'approval' : 'open';
      await tx.query('UPDATE communities SET admission_policy = $1 WHERE id = $2', [policy, input.communityId]);
    }

    return { ok: true, community: (await tx.query('SELECT * FROM communities WHERE id = $1', [input.communityId])).rows[0] };
  });
}

export async function listCommunityMembers(repository: PostgresRepository, communityId: string): Promise<Record<string, unknown>> {
  const community = await repository.query('SELECT * FROM communities WHERE id = $1', [communityId]);
  if (!community.rows[0]) throw new Error('Community not found');
  const members = await repository.query(`
    SELECT 
      cm.community_id, 
      cm.human_id, 
      cm.role, 
      cm.joined_game_day,
      COALESCE(h.display_name, 'Citizen') AS human_name
    FROM community_members cm
    JOIN humans h ON h.id = cm.human_id
    WHERE cm.community_id = $1 
    ORDER BY CASE cm.role WHEN 'founder' THEN 1 WHEN 'admin' THEN 2 ELSE 3 END, cm.joined_game_day, cm.human_id
  `, [communityId]);
  return { community: community.rows[0], members: members.rows };
}

export async function changeCommunityMembership(
  repository: PostgresRepository,
  input: { communityId: string; humanId: string; action: 'join' | 'leave' },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const community = await tx.query<{ id: string; status: string; founder_id: string; admission_policy: string }>('SELECT id, status, founder_id, admission_policy FROM communities WHERE id = $1 FOR UPDATE', [input.communityId]);
    if (!community.rows[0]) throw new Error('Community not found');
    if (community.rows[0].status !== 'active') throw new Error('Community is not active');
    const human = await tx.query<{ id: string }>("SELECT id FROM humans WHERE id = $1 AND life_status = 'active'", [input.humanId]);
    if (!human.rows[0]) throw new Error('Human not found');
    const existing = await tx.query<{ role: string }>('SELECT community_id, role FROM community_members WHERE community_id = $1 AND human_id = $2 FOR UPDATE', [input.communityId, input.humanId]);
    const day = await currentDay(tx);

    if (input.action === 'leave') {
      if (!existing.rows[0]) throw new Error('Human is not a community member');
      const isFounder = community.rows[0].founder_id === input.humanId || existing.rows[0].role === 'founder';
      const memberCountRes = await tx.query<{ count: string }>('SELECT COUNT(*)::integer AS count FROM community_members WHERE community_id = $1', [input.communityId]);
      const memberCount = Number(memberCountRes.rows[0]?.count ?? 1);
      if (isFounder && memberCount > 1) {
        throw new Error('As founder, you cannot leave while other members belong to the community. Appoint a new founder or disband the community.');
      }
      await tx.query('DELETE FROM community_members WHERE community_id = $1 AND human_id = $2', [input.communityId, input.humanId]);
      await tx.query("INSERT INTO membership_events (id, human_id, institution_type, institution_id, action, game_day, reason) VALUES ($1,$2,'COMMUNITY',$3,'left',$4,'voluntary_departure')", [crypto.randomUUID(), input.humanId, input.communityId, day]);
      await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [`COMMUNITY-LEFT-${input.humanId}-${input.communityId}-${day}`, input.humanId, 'community', 'Community left', `You left community ${input.communityId}.`, input.communityId]);
      return { ok: true, membership: null };
    }

    if (existing.rows[0]) throw new Error('Human is already a community member');

    // If admission policy is approval, create a membership request
    if (community.rows[0].admission_policy === 'approval') {
      const pending = await tx.query<{ id: string }>('SELECT id FROM community_membership_requests WHERE community_id = $1 AND human_id = $2 AND status = \'pending\'', [input.communityId, input.humanId]);
      if (pending.rows[0]) {
        return { ok: true, pendingApproval: true, message: 'Membership request is already pending review' };
      }
      const reqId = `REQ-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
      await tx.query('INSERT INTO community_membership_requests (id, community_id, human_id, status, requested_game_day) VALUES ($1,$2,$3,\'pending\',$4)', [reqId, input.communityId, input.humanId, day]);
      
      // Notify founder
      await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [
        `COMMUNITY-REQ-${input.humanId}-${input.communityId}-${day}`, community.rows[0].founder_id, 'community', 'Membership Request', `A citizen requested to join community ${community.rows[0].id}.`, input.communityId,
      ]);
      return { ok: true, pendingApproval: true, requestId: reqId };
    }

    await tx.query("INSERT INTO community_members (community_id, human_id, role, joined_game_day) VALUES ($1,$2,'member',$3)", [input.communityId, input.humanId, day]);
    await tx.query("DELETE FROM community_membership_requests WHERE community_id = $1 AND human_id = $2", [input.communityId, input.humanId]);
    await tx.query("INSERT INTO membership_events (id, human_id, institution_type, institution_id, action, game_day, reason) VALUES ($1,$2,'COMMUNITY',$3,'joined',$4,'voluntary_membership')", [crypto.randomUUID(), input.humanId, input.communityId, day]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [`COMMUNITY-JOINED-${input.humanId}-${input.communityId}-${day}`, input.humanId, 'community', 'Community joined', `You joined community ${input.communityId}.`, input.communityId]);
    return { ok: true, member: (await tx.query('SELECT * FROM community_members WHERE community_id = $1 AND human_id = $2', [input.communityId, input.humanId])).rows[0] };
  });
}

export async function listCommunityMembershipRequests(
  repository: PostgresRepository,
  communityId: string,
  viewerId: string,
): Promise<Record<string, unknown>> {
  const community = await repository.query<{ founder_id: string }>('SELECT founder_id FROM communities WHERE id = $1', [communityId]);
  if (!community.rows[0]) throw new Error('Community not found');
  const member = await repository.query<{ role: string }>('SELECT role FROM community_members WHERE community_id = $1 AND human_id = $2', [communityId, viewerId]);
  const isFounderOrAdmin = community.rows[0].founder_id === viewerId || member.rows[0]?.role === 'founder' || member.rows[0]?.role === 'admin';
  if (!isFounderOrAdmin) throw new Error('Only founder or administrators can view membership requests');

  const requests = await repository.query(`
    SELECT 
      r.id, 
      r.community_id, 
      r.human_id, 
      r.status, 
      r.requested_game_day,
      COALESCE(h.display_name, 'Citizen') AS human_name
    FROM community_membership_requests r
    JOIN humans h ON h.id = r.human_id
    WHERE r.community_id = $1 AND r.status = 'pending'
    ORDER BY r.requested_game_day ASC
  `, [communityId]);

  return { requests: requests.rows };
}

export async function decideCommunityMembershipRequest(
  repository: PostgresRepository,
  input: { communityId: string; deciderId: string; requestId: string; action: 'approve' | 'reject' },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const community = await tx.query<{ founder_id: string }>('SELECT founder_id FROM communities WHERE id = $1', [input.communityId]);
    if (!community.rows[0]) throw new Error('Community not found');
    const member = await tx.query<{ role: string }>('SELECT role FROM community_members WHERE community_id = $1 AND human_id = $2', [input.communityId, input.deciderId]);
    const isFounderOrAdmin = community.rows[0].founder_id === input.deciderId || member.rows[0]?.role === 'founder' || member.rows[0]?.role === 'admin';
    if (!isFounderOrAdmin) throw new Error('Only founder or administrators can decide membership requests');

    const request = await tx.query<{ id: string; human_id: string; status: string }>(
      'SELECT id, human_id, status FROM community_membership_requests WHERE id = $1 AND community_id = $2 FOR UPDATE',
      [input.requestId, input.communityId],
    );
    if (!request.rows[0]) throw new Error('Request not found');
    if (request.rows[0].status !== 'pending') throw new Error('Request already decided');

    const day = await currentDay(tx);
    const applicantId = request.rows[0].human_id;

    if (input.action === 'approve') {
      await tx.query('UPDATE community_membership_requests SET status = \'approved\', decided_game_day = $1, decided_by = $2 WHERE id = $3', [day, input.deciderId, input.requestId]);
      await tx.query("INSERT INTO community_members (community_id, human_id, role, joined_game_day) VALUES ($1,$2,'member',$3) ON CONFLICT (community_id, human_id) DO NOTHING", [input.communityId, applicantId, day]);
      await tx.query("INSERT INTO membership_events (id, human_id, institution_type, institution_id, action, game_day, reason) VALUES ($1,$2,'COMMUNITY',$3,'joined',$4,'approved_application')", [crypto.randomUUID(), applicantId, input.communityId, day]);
      await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [
        `COMMUNITY-APPROVED-${applicantId}-${input.communityId}-${day}`, applicantId, 'community', 'Membership Approved', `Your request to join community ${input.communityId} was approved.`, input.communityId,
      ]);
      return { ok: true, status: 'approved' };
    } else {
      await tx.query('UPDATE community_membership_requests SET status = \'rejected\', decided_game_day = $1, decided_by = $2 WHERE id = $3', [day, input.deciderId, input.requestId]);
      await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [
        `COMMUNITY-REJECTED-${applicantId}-${input.communityId}-${day}`, applicantId, 'community', 'Membership Declined', `Your request to join community ${input.communityId} was declined.`, input.communityId,
      ]);
      return { ok: true, status: 'rejected' };
    }
  });
}

export async function setCommunityMemberRole(
  repository: PostgresRepository,
  input: { communityId: string; actorId: string; targetHumanId: string; role: 'admin' | 'member' },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const community = await tx.query<{ founder_id: string }>('SELECT founder_id FROM communities WHERE id = $1', [input.communityId]);
    if (!community.rows[0]) throw new Error('Community not found');
    if (community.rows[0].founder_id !== input.actorId) throw new Error('Only the community founder can assign administrator roles');
    if (input.targetHumanId === input.actorId) throw new Error('Cannot modify founder role');

    const target = await tx.query('SELECT role FROM community_members WHERE community_id = $1 AND human_id = $2', [input.communityId, input.targetHumanId]);
    if (!target.rows[0]) throw new Error('Target user is not a member of this community');

    const newRole = input.role === 'admin' ? 'admin' : 'member';
    await tx.query('UPDATE community_members SET role = $1 WHERE community_id = $2 AND human_id = $3', [newRole, input.communityId, input.targetHumanId]);
    return { ok: true, targetHumanId: input.targetHumanId, role: newRole };
  });
}

export async function disbandCommunity(
  repository: PostgresRepository,
  input: { communityId: string; humanId: string },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const community = await tx.query<{ id: string; founder_id: string; shared_credits: string }>(
      'SELECT id, founder_id, shared_credits FROM communities WHERE id = $1 FOR UPDATE',
      [input.communityId],
    );
    if (!community.rows[0]) throw new Error('Community not found');
    if (community.rows[0].founder_id !== input.humanId) throw new Error('Only the community founder can disband the community');

    const treasury = Number(community.rows[0].shared_credits ?? 0);
    if (treasury > 0) {
      throw new Error(`Cannot disband community with remaining shared treasury of ${treasury.toFixed(2)} Credits. Disburse or transfer shared funds first.`);
    }

    await tx.query('DELETE FROM community_membership_requests WHERE community_id = $1', [input.communityId]);
    await tx.query('DELETE FROM community_members WHERE community_id = $1', [input.communityId]);
    await tx.query('DELETE FROM communities WHERE id = $1', [input.communityId]);

    const day = await currentDay(tx);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [
      `COMMUNITY-DISBANDED-${input.humanId}-${input.communityId}-${day}`, input.humanId, 'community', 'Community Disbanded', `You disbanded community ${input.communityId}.`, input.communityId,
    ]);

    return { ok: true, disbanded: true, communityId: input.communityId };
  });
}

export async function listCommunityContributions(repository: PostgresRepository, communityId: string): Promise<Record<string, unknown>> {
  const community = await repository.query('SELECT id, name, shared_credits FROM communities WHERE id = $1', [communityId]);
  if (!community.rows[0]) throw new Error('Community not found');
  const entries = await repository.query("SELECT id, game_day, debit_account, credit_account, amount, reason_id, correlation_id, created_at FROM ledger_entries WHERE reason_type = 'community_contribution' AND credit_account = $1 ORDER BY created_at DESC LIMIT 100", [communityId]);
  return { community: community.rows[0], contributions: entries.rows };
}

export async function contributeToCommunity(repository: PostgresRepository, input: { communityId: string; humanId: string; amount: number; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    if (!Number.isFinite(input.amount) || input.amount <= 0) throw new Error('Contribution amount must be positive');
    const prior = await tx.query<{ amount: string; game_day: number }>("SELECT amount, game_day FROM ledger_entries WHERE reason_type = 'community_contribution' AND correlation_id = $1", [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, amount: Number(prior.rows[0].amount), gameDay: Number(prior.rows[0].game_day), correlationId: input.correlationId };
    const community = await tx.query<{ id: string; status: string; shared_credits: string }>('SELECT id, status, shared_credits FROM communities WHERE id = $1 FOR UPDATE', [input.communityId]);
    if (!community.rows[0]) throw new Error('Community not found');
    if (community.rows[0].status !== 'active') throw new Error('Community is not active');
    const membership = await tx.query('SELECT human_id FROM community_members WHERE community_id = $1 AND human_id = $2', [input.communityId, input.humanId]);
    if (!membership.rows[0]) throw new Error('Contributor must be a community member');
    const account = await tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE", [input.humanId]);
    const amountCents = moneyToCents(input.amount);
    const amount = centsToMoney(amountCents);
    const communityAccount = `account-community-${input.communityId}`;
    if (!account.rows[0]) throw new Error('Contributor account not found');
    if (moneyToCents(account.rows[0].balance) < amountCents) throw new Error('Insufficient Credits');
    const day = await currentDay(tx);
    await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: account.rows[0].account_id, creditAccount: communityAccount, amount, reasonType: 'community_contribution', reasonId: input.communityId, ruleVersion: 'community-v2', correlationId: input.correlationId });
    await tx.query('UPDATE communities SET shared_credits = shared_credits + $1 WHERE id = $2', [amount, input.communityId]);
    return { ok: true, amount: Number(amount), correlationId: input.correlationId, community: (await tx.query('SELECT id, name, shared_credits FROM communities WHERE id = $1', [input.communityId])).rows[0], account: (await tx.query('SELECT account_id, balance FROM account_balances WHERE account_id = $1', [account.rows[0].account_id])).rows[0] };
  });
}
