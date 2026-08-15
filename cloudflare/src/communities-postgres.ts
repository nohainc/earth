import type { PostgresRepository } from './repository';
import { transferCredits } from './financial-postgres';
import { centsToMoney, moneyToCents } from './money';

const MAX_NAME_LENGTH = 80;

function requireName(name: string): string {
  const normalized = name.trim();
  if (normalized.length < 3 || normalized.length > MAX_NAME_LENGTH) {
    throw new Error('Community name must be 3–80 characters');
  }
  return normalized;
}

async function currentDay(repository: PostgresRepository): Promise<number> {
  const result = await repository.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
  return Number(result.rows[0]?.game_day ?? 0);
}

export async function listCommunities(repository: PostgresRepository): Promise<Record<string, unknown>> {
  const result = await repository.query('SELECT * FROM communities ORDER BY id');
  return { communities: result.rows };
}

export async function createCommunity(repository: PostgresRepository, input: { founderId: string; name: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const name = requireName(input.name);
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
    await tx.query('INSERT INTO communities (id, name, founder_id, shared_credits) VALUES ($1,$2,$3,0)', [communityId, name, input.founderId]);
    await tx.query("INSERT INTO account_balances (account_id, owner_id, balance, currency) VALUES ($1, $2, 0, 'CREDIT')", [`account-community-${communityId}`, communityId]);
    await tx.query("INSERT INTO community_members (community_id, human_id, role, joined_game_day) VALUES ($1,$2,'founder',$3)", [communityId, input.founderId, day]);
    await tx.query("INSERT INTO membership_events (id, human_id, institution_type, institution_id, action, game_day, reason) VALUES ($1,$2,'COMMUNITY',$3,'joined',$4,'community_formation')", [input.correlationId, input.founderId, communityId, day]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [
      `COMMUNITY-FOUNDED-${input.founderId}-${communityId}`, input.founderId, 'community', 'Community founded', `You founded community ${communityId}.`, communityId,
    ]);
    return { ok: true, community: (await tx.query('SELECT * FROM communities WHERE id = $1', [communityId])).rows[0], correlationId: input.correlationId };
  });
}

export async function listCommunityMembers(repository: PostgresRepository, communityId: string): Promise<Record<string, unknown>> {
  const community = await repository.query('SELECT * FROM communities WHERE id = $1', [communityId]);
  if (!community.rows[0]) throw new Error('Community not found');
  const members = await repository.query('SELECT community_id, human_id, role, joined_game_day FROM community_members WHERE community_id = $1 ORDER BY joined_game_day, human_id', [communityId]);
  return { community: community.rows[0], members: members.rows };
}

export async function changeCommunityMembership(repository: PostgresRepository, input: { communityId: string; humanId: string; action: 'join' | 'leave' }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const community = await tx.query<{ id: string; status: string }>('SELECT id, status FROM communities WHERE id = $1 FOR UPDATE', [input.communityId]);
    if (!community.rows[0]) throw new Error('Community not found');
    if (community.rows[0].status !== 'active') throw new Error('Community is not active');
    const human = await tx.query<{ id: string }>("SELECT id FROM humans WHERE id = $1 AND life_status = 'active'", [input.humanId]);
    if (!human.rows[0]) throw new Error('Human not found');
    const existing = await tx.query('SELECT community_id FROM community_members WHERE community_id = $1 AND human_id = $2 FOR UPDATE', [input.communityId, input.humanId]);
    const day = await currentDay(tx);
    if (input.action === 'leave') {
      if (!existing.rows[0]) throw new Error('Human is not a community member');
      await tx.query('DELETE FROM community_members WHERE community_id = $1 AND human_id = $2', [input.communityId, input.humanId]);
      await tx.query("INSERT INTO membership_events (id, human_id, institution_type, institution_id, action, game_day, reason) VALUES ($1,$2,'COMMUNITY',$3,'left',$4,'voluntary_departure')", [crypto.randomUUID(), input.humanId, input.communityId, day]);
      await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [`COMMUNITY-LEFT-${input.humanId}-${input.communityId}-${day}`, input.humanId, 'community', 'Community left', `You left community ${input.communityId}.`, input.communityId]);
      return { ok: true, membership: null };
    }
    if (existing.rows[0]) throw new Error('Human is already a community member');
    await tx.query("INSERT INTO community_members (community_id, human_id, role, joined_game_day) VALUES ($1,$2,'member',$3)", [input.communityId, input.humanId, day]);
    await tx.query("INSERT INTO membership_events (id, human_id, institution_type, institution_id, action, game_day, reason) VALUES ($1,$2,'COMMUNITY',$3,'joined',$4,'voluntary_membership')", [crypto.randomUUID(), input.humanId, input.communityId, day]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [`COMMUNITY-JOINED-${input.humanId}-${input.communityId}-${day}`, input.humanId, 'community', 'Community joined', `You joined community ${input.communityId}.`, input.communityId]);
    return { ok: true, member: (await tx.query('SELECT * FROM community_members WHERE community_id = $1 AND human_id = $2', [input.communityId, input.humanId])).rows[0] };
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
