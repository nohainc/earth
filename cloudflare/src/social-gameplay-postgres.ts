import type { PostgresRepository } from './repository.ts';
import { transferCredits } from './financial-postgres.ts';

const KINDS = ['alliance', 'negotiation', 'campaign', 'announcement', 'lobbying', 'shared_project', 'agreement'] as const;
export type SocialKind = typeof KINDS[number];
const PROJECT_EFFECTS = ['housing', 'energy', 'connectivity', 'health', 'corporation_treasury'] as const;
type ProjectEffect = typeof PROJECT_EFFECTS[number];

function projectTerms(value: unknown): Record<string, unknown> {
  if (value && typeof value === 'object') return value as Record<string, unknown>;
  if (typeof value === 'string') {
    try { return JSON.parse(value) as Record<string, unknown>; } catch (_error) { return {}; }
  }
  return {};
}

export async function listSocialInitiatives(repo: PostgresRepository, humanId: string) {
  const result = await repo.query(`
    SELECT si.*, sim.status AS member_status, sim.role AS member_role, sim.contribution
    FROM social_initiatives si
    LEFT JOIN social_initiative_members sim ON sim.initiative_id = si.id AND sim.human_id = $1
    WHERE si.creator_human_id = $1 OR si.target_human_id = $1 OR sim.human_id = $1
    ORDER BY si.updated_at DESC LIMIT 100`, [humanId]);
  return result.rows;
}

export async function listSocialTimeline(repo: PostgresRepository, humanId: string, limit = 50) {
  const result = await repo.query(`
    SELECT we.id, we.game_day, we.event_type AS type, we.title, we.details, we.created_at
    FROM world_events we
    LEFT JOIN social_initiatives si ON si.id = we.details::jsonb->>'initiativeId'
    WHERE we.event_type LIKE 'social.%'
      AND (si.kind IN ('announcement','campaign') OR si.creator_human_id = $1 OR si.target_human_id = $1 OR EXISTS (SELECT 1 FROM social_initiative_members sim WHERE sim.initiative_id = si.id AND sim.human_id = $1))
    ORDER BY game_day DESC, created_at DESC LIMIT $2`, [humanId, Math.min(100, Math.max(1, limit))]);
  return result.rows;
}

export async function listSocialRelationships(repo: PostgresRepository, humanId: string) {
  const result = await repo.query(`SELECT r.*, h.display_name, d.dynasty_name FROM social_relationships r JOIN humans h ON h.id = r.other_human_id LEFT JOIN dynasties d ON d.founder_human_id = h.id WHERE r.human_id = $1 ORDER BY r.trust DESC, h.display_name LIMIT 50`, [humanId]);
  return result.rows;
}

async function updateRelationship(repo: PostgresRepository, first: string, second: string, trust: number, completed = 0, broken = 0, day?: number) {
  if (!second || first === second) return;
  await repo.query(`INSERT INTO social_relationships (human_id, other_human_id, trust, public_reputation, completed_agreements, broken_commitments, last_interaction_game_day) VALUES ($1,$2,$3,$3,$4,$5,$6) ON CONFLICT (human_id, other_human_id) DO UPDATE SET trust = social_relationships.trust + EXCLUDED.trust, public_reputation = social_relationships.public_reputation + EXCLUDED.public_reputation, completed_agreements = social_relationships.completed_agreements + EXCLUDED.completed_agreements, broken_commitments = social_relationships.broken_commitments + EXCLUDED.broken_commitments, last_interaction_game_day = EXCLUDED.last_interaction_game_day`, [first, second, trust, completed, broken, day ?? null]);
}

export async function listSocialDirectory(repo: PostgresRepository, viewerId: string, query = '') {
  const term = `%${query.trim().slice(0, 80)}%`;
  const [humans, businesses, cities, corporations, communities, initiatives] = await Promise.all([
    repo.query(`SELECT h.id, h.display_name, d.dynasty_name, h.standing, h.legacy, m.city_id, ci.id AS city_name FROM humans h LEFT JOIN dynasties d ON d.founder_human_id = h.id LEFT JOIN memberships m ON m.human_id = h.id LEFT JOIN cities ci ON ci.id = m.city_id WHERE h.life_status = 'active' AND h.id <> $1 AND ($2 = '%%' OR h.display_name ILIKE $2 OR d.dynasty_name ILIKE $2) ORDER BY h.standing DESC LIMIT 40`, [viewerId, term]),
    repo.query(`SELECT id, name, sector, status, owner_id FROM businesses WHERE status = 'active' AND ($1 = '%%' OR name ILIKE $1) ORDER BY name LIMIT 30`, [term]),
    repo.query(`SELECT id, name, status, residents, treasury FROM cities WHERE status = 'active' AND ($1 = '%%' OR name ILIKE $1) ORDER BY residents DESC LIMIT 30`, [term]),
    repo.query(`SELECT id, name, status, member_count, treasury FROM corporations WHERE status = 'active' AND ($1 = '%%' OR name ILIKE $1) ORDER BY member_count DESC LIMIT 30`, [term]),
    repo.query(`SELECT id, name, status, member_count, shared_credits FROM communities WHERE status = 'active' AND ($1 = '%%' OR name ILIKE $1) ORDER BY member_count DESC LIMIT 30`, [term]),
    repo.query(`SELECT id, kind, title, status, progress, deadline_game_day FROM social_initiatives WHERE status IN ('proposed','active') AND ($1 = '%%' OR title ILIKE $1) ORDER BY updated_at DESC LIMIT 30`, [term]),
  ]);
  return { humans: humans.rows, businesses: businesses.rows.map(({ owner_id, ...row }) => row), cities: cities.rows, corporations: corporations.rows, communities: communities.rows, initiatives: initiatives.rows };
}

export async function createSocialInitiative(repo: PostgresRepository, input: {
  creatorId: string; targetId?: string | null; kind: SocialKind; title: string; body: string;
  terms?: Record<string, unknown>; gameDay?: number;
}) {
  if (!KINDS.includes(input.kind)) throw new Error('Unsupported social initiative kind');
  if (input.targetId === input.creatorId) throw new Error('A social initiative needs another participant');
  const creditAmount = Number(input.terms?.creditAmount ?? 0);
  const deadline = Number(input.terms?.deadlineGameDay ?? (input.gameDay ?? 1) + 7);
  const contributionTarget = Number(input.terms?.contributionTarget ?? 100);
  if (!Number.isFinite(creditAmount) || creditAmount < 0 || creditAmount > 1_000_000) throw new Error('Credit amount must be between 0 and 1,000,000');
  if (!Number.isInteger(deadline) || deadline <= Number(input.gameDay ?? 1) || deadline > Number(input.gameDay ?? 1) + 365) throw new Error('Deadline must be 1–365 game days after creation');
  if (!Number.isInteger(contributionTarget) || contributionTarget < 1 || contributionTarget > 100) throw new Error('Contribution target must be between 1 and 100');
  const institutionId = String(input.terms?.institutionId ?? '').trim();
  const projectEffect = String(input.terms?.projectEffect ?? '').trim() as ProjectEffect;
  const projectAmount = Number(input.terms?.projectAmount ?? 0);
  if (input.kind === 'shared_project') {
    if (!institutionId || !PROJECT_EFFECTS.includes(projectEffect)) throw new Error('A shared project needs a supported city or corporation effect');
    if (!Number.isInteger(projectAmount) || projectAmount < 1 || projectAmount > (projectEffect === 'corporation_treasury' ? 5000 : 100)) throw new Error('Project effect amount is outside the allowed range');
  }
  const id = `social-${crypto.randomUUID()}`;
  const result = await repo.transaction(async (tx) => {
    if (input.kind === 'shared_project') {
      const institution = (await tx.query<{ kind: string }>('SELECT kind FROM institutions WHERE id = $1 AND status = \'active\'', [institutionId])).rows[0];
      if (!institution || !['CITY', 'CORPORATION'].includes(institution.kind)) throw new Error('Project institution must be an active city or corporation');
      const membership = institution.kind === 'CITY'
        ? await tx.query('SELECT 1 FROM memberships WHERE human_id = $1 AND city_id = $2', [input.creatorId, institutionId])
        : await tx.query('SELECT 1 FROM memberships WHERE human_id = $1 AND corporation_id = $2', [input.creatorId, institutionId]);
      if (!membership.rows[0]) throw new Error('Project creator must belong to its city or corporation');
      if (projectEffect === 'corporation_treasury' && institution.kind !== 'CORPORATION') throw new Error('Treasury projects require a corporation');
      if (projectEffect !== 'corporation_treasury' && institution.kind !== 'CITY') throw new Error('Service projects require a city');
    }
    const created = await tx.query(`INSERT INTO social_initiatives
      (id, creator_human_id, target_human_id, kind, title, body, terms, deadline_game_day, escrow_amount, escrow_status, game_day, status)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING *`, [id, input.creatorId, input.targetId ?? null, input.kind, input.title, input.body, JSON.stringify({ ...(input.terms ?? {}), contributionTarget }), deadline, creditAmount, creditAmount > 0 ? 'locked' : 'none', input.gameDay ?? 1, input.kind === 'announcement' || input.kind === 'campaign' ? 'active' : 'proposed']);
    if (creditAmount > 0) {
      const account = (await tx.query<{ account_id: string }>("SELECT account_id FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE", [input.creatorId])).rows[0];
      if (!account) throw new Error('Creator credit account is missing');
      const escrowAccount = `social-${id}`;
      await tx.query("INSERT INTO account_balances (account_id, owner_id, balance, currency) VALUES ($1,$1,0,'CREDIT')", [escrowAccount]);
      await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: input.gameDay ?? 1, debitAccount: account.account_id, creditAccount: escrowAccount, amount: creditAmount, reasonType: 'social_escrow_lock', reasonId: id, ruleVersion: 'social-v1', correlationId: id });
    }
    await tx.query(`INSERT INTO social_initiative_members (initiative_id, human_id, role, status) VALUES ($1,$2,'creator',$3)`, [id, input.creatorId, input.kind === 'announcement' || input.kind === 'campaign' ? 'accepted' : 'accepted']);
    if (input.targetId) await tx.query(`INSERT INTO social_initiative_members (initiative_id, human_id, role) VALUES ($1,$2,'counterparty')`, [id, input.targetId]);
    const delta = input.kind === 'announcement' ? 2 : input.kind === 'campaign' ? 3 : 1;
    await tx.query('UPDATE humans SET standing = standing + $1 WHERE id = $2', [delta, input.creatorId]);
    if (input.targetId) await tx.query("INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,'social','Social initiative invitation',$3,$4) ON CONFLICT DO NOTHING", [`SOCIAL-INVITE-${id}`, input.targetId, `${input.title} needs your response`, `${input.body} Open the Social panel to accept or decline.`, id]);
    if (input.targetId) { await updateRelationship(tx, input.creatorId, input.targetId, 1, 0, 0, input.gameDay); await updateRelationship(tx, input.targetId, input.creatorId, 1, 0, 0, input.gameDay); }
    await tx.query("INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,'social.initiative_created',$3,$4) ON CONFLICT DO NOTHING", [`SOCIAL-CREATED-${id}`, input.gameDay ?? 1, `${input.title} was proposed`, JSON.stringify({ initiativeId: id, kind: input.kind, creatorId: input.creatorId })]);
    return created.rows[0];
  });
  return result;
}

async function applyCompletedProject(tx: PostgresRepository, initiative: any, gameDay: number): Promise<void> {
  const terms = projectTerms(initiative.terms);
  if (initiative.kind !== 'shared_project') return;
  const institutionId = String(terms.institutionId ?? '').trim();
  const effect = String(terms.projectEffect ?? '').trim() as ProjectEffect;
  const amount = Number(terms.projectAmount ?? 0);
  if (!institutionId || !PROJECT_EFFECTS.includes(effect) || !Number.isInteger(amount) || amount < 1) return;
  if (effect === 'corporation_treasury') {
    await tx.query('UPDATE corporations SET treasury = treasury + $1 WHERE id = $2', [amount, institutionId]);
  } else {
    const column = { housing: 'housing_capacity', energy: 'energy_capacity', connectivity: 'connectivity_capacity', health: 'health_capacity' }[effect];
    if (!column) return;
    await tx.query(`UPDATE cities SET ${column} = ${column} + $1 WHERE id = $2`, [amount, institutionId]);
  }
  await tx.query("INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,'institution.project_completed',$3,$4) ON CONFLICT DO NOTHING", [`PROJECT-EFFECT-${initiative.id}`, gameDay, `${initiative.title} improved its institution`, JSON.stringify({ initiativeId: initiative.id, institutionId, effect, amount })]);
}

export async function respondToSocialInitiative(repo: PostgresRepository, humanId: string, initiativeId: string, accept: boolean) {
  return repo.transaction(async (tx) => {
    const row = (await tx.query<any>('SELECT * FROM social_initiatives WHERE id = $1 FOR UPDATE', [initiativeId])).rows[0];
    if (!row || row.target_human_id !== humanId) throw new Error('Social initiative is not addressed to this human');
    if (row.status !== 'proposed') throw new Error('This social initiative no longer accepts responses');
    const membership = (await tx.query<any>('SELECT status FROM social_initiative_members WHERE initiative_id = $1 AND human_id = $2 FOR UPDATE', [initiativeId, humanId])).rows[0];
    if (!membership || membership.status !== 'invited') throw new Error('This invitation has already been answered');
    const status = accept ? 'accepted' : 'declined';
    await tx.query('UPDATE social_initiative_members SET status = $1 WHERE initiative_id = $2 AND human_id = $3', [status, initiativeId, humanId]);
    await tx.query('UPDATE social_initiatives SET status = $1, updated_at = NOW() WHERE id = $2', [accept ? 'active' : 'declined', initiativeId]);
    await tx.query('UPDATE humans SET standing = standing + $1 WHERE id = $2', [accept ? 2 : -1, humanId]);
    await updateRelationship(tx, humanId, row.creator_human_id, accept ? 3 : -2, 0, accept ? 0 : 1, row.game_day); await updateRelationship(tx, row.creator_human_id, humanId, accept ? 3 : -2, 0, accept ? 0 : 1, row.game_day);
    await tx.query("INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,'social',$3,$4,$5) ON CONFLICT DO NOTHING", [`SOCIAL-RESPONSE-${initiativeId}-${humanId}`, row.creator_human_id, accept ? 'Social initiative accepted' : 'Social initiative declined', `${row.title} was ${accept ? 'accepted' : 'declined'}.`, initiativeId]);
    await tx.query("INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,(SELECT game_day FROM world_state WHERE id='WORLD'),'social.initiative_response',$2,$3) ON CONFLICT DO NOTHING", [`SOCIAL-RESPONSE-${initiativeId}-${humanId}`, `${row.title} was ${accept ? 'accepted' : 'declined'}`, JSON.stringify({ initiativeId, humanId, accept })]);
    return { ...row, status };
  });
}

export async function contributeToSocialInitiative(repo: PostgresRepository, humanId: string, initiativeId: string, contribution: number) {
  if (!Number.isInteger(contribution) || contribution < 1 || contribution > 100) throw new Error('Contribution must be an integer from 1 to 100');
  return repo.transaction(async (tx) => {
    const initiative = (await tx.query<any>("SELECT * FROM social_initiatives WHERE id = $1 FOR UPDATE", [initiativeId])).rows[0];
    if (!initiative || initiative.status !== 'active') throw new Error('This initiative is not accepting contributions');
    const currentDay = Number((await tx.query<any>("SELECT game_day FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? initiative.game_day);
    if (initiative.deadline_game_day != null && currentDay > Number(initiative.deadline_game_day)) throw new Error('This initiative has expired');
    const member = (await tx.query<any>('SELECT * FROM social_initiative_members WHERE initiative_id = $1 AND human_id = $2 FOR UPDATE', [initiativeId, humanId])).rows[0];
    if (!member || member.status !== 'accepted') throw new Error('Accept the initiative before contributing');
    await tx.query('UPDATE social_initiative_members SET contribution = contribution + $1 WHERE initiative_id = $2 AND human_id = $3', [contribution, initiativeId, humanId]);
    const remaining = Math.max(0, Number(initiative.terms?.contributionTarget ?? 100) - Number(initiative.progress));
    const applied = Math.min(contribution, remaining);
    if (applied <= 0) throw new Error('This initiative is already complete');
    const newProgress = Math.min(100, Number(initiative.progress) + applied);
    const isComplete = newProgress >= Number(initiative.terms?.contributionTarget ?? 100);
    const result = await tx.query<any>(`UPDATE social_initiatives SET progress = $1, status = $2, updated_at = NOW() WHERE id = $3 AND status = 'active' RETURNING *`, [newProgress, isComplete ? 'completed' : 'active', initiativeId]);
    if (!result.rows[0]) throw new Error('This initiative is no longer accepting contributions');
    await tx.query('UPDATE humans SET standing = standing + 1, legacy = legacy + CASE WHEN $1 >= 100 THEN 1 ELSE 0 END WHERE id = $2', [result.rows[0].progress, humanId]);
    if (Number(result.rows[0].progress) >= 100) {
      const initiative = (await tx.query<any>('SELECT * FROM social_initiatives WHERE id = $1 FOR UPDATE', [initiativeId])).rows[0];
      if (initiative.escrow_status === 'locked' && Number(initiative.escrow_amount) > 0) {
        const escrowAccount = `social-${initiativeId}`;
        const recipient = (await tx.query<{ account_id: string }>("SELECT account_id FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [initiative.creator_human_id])).rows[0];
        if (recipient) await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: Number(initiative.game_day), debitAccount: escrowAccount, creditAccount: recipient.account_id, amount: initiative.escrow_amount, reasonType: 'social_escrow_release', reasonId: initiativeId, ruleVersion: 'social-v1', correlationId: `RELEASE-${initiativeId}` });
      await tx.query("UPDATE social_initiatives SET escrow_status='released' WHERE id=$1", [initiativeId]);
      await applyCompletedProject(tx, initiative, currentDay);
      for (const member of (await tx.query<{ human_id: string }>('SELECT human_id FROM social_initiative_members WHERE initiative_id = $1', [initiativeId])).rows) {
        for (const other of (await tx.query<{ human_id: string }>('SELECT human_id FROM social_initiative_members WHERE initiative_id = $1 AND human_id <> $2', [initiativeId, member.human_id])).rows) await updateRelationship(tx, member.human_id, other.human_id, 5, 1, 0, Number(initiative.game_day));
      }
      }
      await tx.query("INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) SELECT 'SOCIAL-COMPLETE-' || $1, human_id, 'social', 'Shared social initiative completed', 'Your contribution completed ' || $2 || '.', $1 FROM social_initiative_members WHERE initiative_id = $1 ON CONFLICT DO NOTHING", [initiativeId, result.rows[0].title]);
      await tx.query("INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,(SELECT game_day FROM world_state WHERE id='WORLD'),'social.initiative_completed',$2,$3) ON CONFLICT DO NOTHING", [`SOCIAL-COMPLETE-${initiativeId}`, `${result.rows[0].title} was completed`, JSON.stringify({ initiativeId })]);
    }
    return result.rows[0];
  });
}

export async function expireSocialInitiatives(repository: PostgresRepository, gameDay: number) {
  return repository.transaction(async (tx) => {
    const expired = await tx.query<any>(`UPDATE social_initiatives SET status = 'expired', escrow_status = CASE WHEN escrow_status = 'locked' THEN 'forfeited' ELSE escrow_status END, updated_at = NOW() WHERE status IN ('proposed','active') AND deadline_game_day IS NOT NULL AND deadline_game_day < $1 RETURNING *`, [gameDay]);
    for (const initiative of expired.rows) {
      const escrow = `social-${initiative.id}`;
      const target = (await tx.query<{ account_id: string }>("SELECT account_id FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [initiative.target_human_id ?? initiative.creator_human_id])).rows[0];
      if (target && Number(initiative.escrow_amount) > 0 && initiative.escrow_status === 'forfeited') {
        await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay, debitAccount: escrow, creditAccount: target.account_id, amount: initiative.escrow_amount, reasonType: 'social_escrow_forfeit', reasonId: initiative.id, ruleVersion: 'social-v1', correlationId: `FORFEIT-${initiative.id}` });
      }
      await tx.query("INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) SELECT 'SOCIAL-EXPIRED-' || $1, human_id, 'social', 'Social initiative expired', 'The initiative deadline passed without completion.', $1 FROM social_initiative_members WHERE initiative_id = $1 ON CONFLICT DO NOTHING", [initiative.id]);
      await tx.query("INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,'social.initiative_expired',$3,$4) ON CONFLICT DO NOTHING", [`SOCIAL-EXPIRED-${initiative.id}`, gameDay, `${initiative.title} expired`, JSON.stringify({ initiativeId: initiative.id })]);
    }
    return expired.rows.length;
  });
}
