import type { PostgresRepository } from './repository.ts';
import { createGameEvent } from './game-events-postgres.ts';
import { calculateMatching } from './public-projects.ts';

async function day(tx: PostgresRepository): Promise<number> { return Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1); }

export async function createPublicProject(repository: PostgresRepository, input: { name: string; description: string; beneficiaryType: 'ORGANIZATION' | 'EARTH' | 'TERRITORY'; beneficiaryId: string; recipientAccountId: string; targetUnits: string; deadlineGameDay: number; matchingPoolAuthorizedUnits: string; proposalId: string; humanId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ id: string }>('SELECT id FROM public_projects WHERE correlation_id = $1', [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, projectId: prior.rows[0].id, correlationId: input.correlationId };
    const proposal = (await tx.query<{ status: string; subject_type: string; subject_id: string | null; action_type: string }>('SELECT status, subject_type, subject_id, action_type FROM governance_proposals_v4 WHERE id = $1', [input.proposalId])).rows[0];
    if (!proposal || proposal.action_type !== 'PUBLIC_PROJECT' || proposal.subject_type !== 'EARTH' || proposal.subject_id !== null || !['VOTING', 'PASSED'].includes(proposal.status)) throw new Error('Public projects require an EARTH public-project proposal');
    const target = BigInt(input.targetUnits); const pool = BigInt(input.matchingPoolAuthorizedUnits);
    if (!input.name.trim() || input.name.trim().length > 120 || target <= 0n || pool < 0n || input.deadlineGameDay < 1) throw new Error('Invalid public project definition');
    const recipient = (await tx.query<{ id: string }>('SELECT id::TEXT FROM economic_accounts WHERE id = $1 AND asset_id = 1 AND status = \'ACTIVE\'', [input.recipientAccountId])).rows[0];
    if (!recipient) throw new Error('Public project recipient account is unavailable');
    const current = await day(tx); const id = `PUBLIC-PROJECT-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    await tx.query(`INSERT INTO public_projects (id, name, description, beneficiary_type, beneficiary_id, recipient_account_id, target_units, deadline_game_day, matching_pool_authorized_units, proposal_id, created_by_human_id, created_game_day, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)`, [id, input.name.trim(), input.description.trim(), input.beneficiaryType, input.beneficiaryId, recipient.id, target.toString(), input.deadlineGameDay, pool.toString(), input.proposalId, input.humanId, current, input.correlationId]);
    return { ok: true, projectId: id, status: 'OPEN', correlationId: input.correlationId };
  });
}

export async function fundMatchingPool(repository: PostgresRepository, input: { projectId: string; proposalId: string; amountUnits: string; humanId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ id: string }>('SELECT id FROM public_project_matching_funds WHERE correlation_id = $1', [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, projectId: input.projectId, correlationId: input.correlationId };
    const proposal = (await tx.query<{ status: string; subject_type: string; subject_id: string | null }>('SELECT status, subject_type, subject_id FROM governance_proposals_v4 WHERE id = $1', [input.proposalId])).rows[0];
    if (!proposal || proposal.status !== 'PASSED' || proposal.subject_type !== 'EARTH' || proposal.subject_id !== null) throw new Error('Matching pools require a passed EARTH proposal');
    const project = (await tx.query<{ matching_pool_authorized_units: string; matching_pool_funded_units: string; deadline_game_day: number }>('SELECT matching_pool_authorized_units::TEXT, matching_pool_funded_units::TEXT, deadline_game_day FROM public_projects WHERE id = $1 AND status IN (\'OPEN\',\'FUNDED\') FOR UPDATE', [input.projectId])).rows[0];
    const amount = BigInt(input.amountUnits);
    if (!project || amount <= 0n || BigInt(project.matching_pool_funded_units) + amount > BigInt(project.matching_pool_authorized_units)) throw new Error('Matching pool authority exceeded');
    const treasury = (await tx.query<{ balance_units: string }>('SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = \'ECON-EARTH-001\' AND account_type = \'TREASURY\' AND asset_id = 1 AND status = \'ACTIVE\' FOR UPDATE')).rows[0];
    if (!treasury || BigInt(treasury.balance_units) < amount) throw new Error('EARTH matching pool cash is insufficient');
    await tx.query("UPDATE public_projects SET matching_pool_funded_units = matching_pool_funded_units + $1 WHERE id = $2", [amount.toString(), input.projectId]);
    await tx.query(`INSERT INTO public_project_matching_funds (id, project_id, amount_units, authorized_game_day, proposal_id, correlation_id) VALUES ($1,$2,$3,(SELECT game_day FROM world_state WHERE id = 'WORLD'),$4,$5)`, [`MATCH-FUND-${input.correlationId}`, input.projectId, amount.toString(), input.proposalId, input.correlationId]);
    return { ok: true, projectId: input.projectId, fundedUnits: (BigInt(project.matching_pool_funded_units) + amount).toString(), correlationId: input.correlationId };
  });
}

export async function listPublicProjects(repository: PostgresRepository): Promise<Record<string, unknown>> {
  const projects = await repository.query(`SELECT p.id, p.name, p.description, p.beneficiary_type, p.beneficiary_id, p.target_units::TEXT, p.deadline_game_day, p.matching_pool_authorized_units::TEXT, p.matching_pool_funded_units::TEXT, p.contribution_units::TEXT, p.matched_units::TEXT, p.status, p.proposal_id, p.created_game_day, COUNT(c.id)::INTEGER AS supporter_count FROM public_projects p LEFT JOIN public_project_contributions c ON c.project_id = p.id AND c.status = 'ESCROWED' GROUP BY p.id ORDER BY p.status, p.deadline_game_day, p.id`);
  return { projects: projects.rows, generatedFrom: 'postgres-canonical-facts' };
}

export async function getPublicProject(repository: PostgresRepository, projectId: string): Promise<Record<string, unknown>> {
  const result = await repository.query<any>(`SELECT p.*, COUNT(DISTINCT c.house_id)::INTEGER AS supporter_count FROM public_projects p LEFT JOIN public_project_contributions c ON c.project_id = p.id AND c.status = 'ESCROWED' WHERE p.id = $1 GROUP BY p.id`, [projectId]);
  const project = result.rows[0];
  if (!project) throw new Error('Public project not found');
  const match = calculateMatching({ contributionUnits: BigInt(project.contribution_units), supporterCount: BigInt(project.supporter_count), poolRemaining: BigInt(project.matching_pool_funded_units) - BigInt(project.matching_pool_spent_units), targetRemaining: BigInt(project.target_units) > BigInt(project.contribution_units) ? BigInt(project.target_units) - BigInt(project.contribution_units) : 0n, matchBps: 10000n });
  return { project: { ...project, projected_match_units: match.toString() }, generatedFrom: 'postgres-canonical-facts' };
}

export async function contributeToPublicProject(repository: PostgresRepository, input: { projectId: string; houseId: string; sourceAccountId: string; amountUnits: string; humanId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ id: string }>('SELECT id FROM public_project_contributions WHERE correlation_id = $1', [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, contributionId: prior.rows[0].id, correlationId: input.correlationId };
    const project = (await tx.query<{ recipient_account_id: string; deadline_game_day: number; status: string; target_units: string; contribution_units: string }>('SELECT recipient_account_id::TEXT, deadline_game_day, status, target_units::TEXT, contribution_units::TEXT FROM public_projects WHERE id = $1 FOR UPDATE', [input.projectId])).rows[0];
    const amount = BigInt(input.amountUnits);
    if (!project || !['OPEN', 'FUNDED'].includes(project.status) || amount <= 0n) throw new Error('Public project is not accepting contributions');
    const current = await day(tx);
    if (current > Number(project.deadline_game_day)) throw new Error('Public project deadline has passed');
    if (BigInt(project.contribution_units) + amount > BigInt(project.target_units)) throw new Error('Contribution exceeds project target');
    const source = (await tx.query<{ id: string; balance_units: string }>('SELECT id::TEXT, balance_units::TEXT FROM economic_accounts WHERE id = $1 AND owner_economic_id = (SELECT economic_id FROM owner_registry WHERE id = $2 AND owner_type = \'HOUSE\') AND asset_id = 1 AND account_type = \'WALLET\' AND status = \'ACTIVE\' FOR UPDATE', [input.sourceAccountId, input.houseId])).rows[0];
    const escrow = (await tx.query<{ id: string }>('SELECT id::TEXT FROM economic_accounts WHERE owner_economic_id = (SELECT economic_id FROM owner_registry WHERE id = \'ECON-CONSTRUCTION-SETTLEMENT\') AND asset_id = 1 AND account_type = \'SYSTEM_ACCOUNT\' AND status = \'ACTIVE\' LIMIT 1')).rows[0];
    if (!source || !escrow || BigInt(source.balance_units) < amount) throw new Error('Contribution wallet balance or project escrow is unavailable');
    const posted = await tx.query<{ transaction_id: string; created: boolean }>('SELECT transaction_id, created FROM earth_post_transaction($1,$2,0,\'PUBLIC_PROJECT_CONTRIBUTION\',\'HOUSE\',$3,\'public-projects-v1\',$4::JSONB)', [input.correlationId, current, input.houseId, JSON.stringify([{ account_id: source.id, asset_id: 1, delta_units: (-amount).toString() }, { account_id: escrow.id, asset_id: 1, delta_units: amount.toString() }])]);
    if (!posted.rows[0]?.created) return { ok: true, alreadyProcessed: true, correlationId: input.correlationId };
    const contributionId = `CONTRIB-${input.correlationId}`;
    await tx.query(`INSERT INTO public_project_contributions (id, project_id, house_id, amount_units, escrow_account_id, contribution_transaction_id, correlation_id, created_game_day) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`, [contributionId, input.projectId, input.houseId, amount.toString(), escrow.id, posted.rows[0].transaction_id, input.correlationId, current]);
    await tx.query('UPDATE public_projects SET contribution_units = contribution_units + $1 WHERE id = $2', [amount.toString(), input.projectId]);
    return { ok: true, contributionId, projectId: input.projectId, amountUnits: amount.toString(), correlationId: input.correlationId };
  });
}

export async function settlePublicProjectInTransaction(tx: PostgresRepository, projectId: string, gameDay: number): Promise<Record<string, unknown>> {
    const project = (await tx.query<any>('SELECT * FROM public_projects WHERE id = $1 FOR UPDATE', [projectId])).rows[0];
    if (!project || project.status === 'SETTLED' || project.status === 'FAILED') return { ok: true, alreadyProcessed: true, projectId };
    if (gameDay < Number(project.deadline_game_day)) throw new Error('Public project deadline is not reached');
    const supporters = await tx.query<{ count: string }>("SELECT COUNT(DISTINCT house_id)::TEXT AS count FROM public_project_contributions WHERE project_id = $1 AND status = 'ESCROWED'", [projectId]);
    const contributed = BigInt(project.contribution_units);
    const target = BigInt(project.target_units);
    const match = calculateMatching({ contributionUnits: contributed, supporterCount: BigInt(supporters.rows[0]?.count ?? 0), poolRemaining: BigInt(project.matching_pool_funded_units) - BigInt(project.matching_pool_spent_units), targetRemaining: target > contributed ? target - contributed : 0n, matchBps: 10000n });
    const funded = contributed + match >= target;
    let settlementTransactionId: string | null = null;
    if (funded && contributed > 0n) {
      const escrow = (await tx.query<{ id: string }>('SELECT id::TEXT FROM economic_accounts WHERE owner_economic_id = (SELECT economic_id FROM owner_registry WHERE id = \'ECON-CONSTRUCTION-SETTLEMENT\') AND asset_id = 1 AND account_type = \'SYSTEM_ACCOUNT\' AND status = \'ACTIVE\' LIMIT 1')).rows[0];
      const earth = (await tx.query<{ id: string; balance_units: string }>('SELECT id::TEXT, balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = \'ECON-EARTH-001\' AND asset_id = 1 AND account_type = \'TREASURY\' AND status = \'ACTIVE\' FOR UPDATE')).rows[0];
      const destination = (await tx.query<{ id: string }>('SELECT id::TEXT FROM economic_accounts WHERE id = $1 AND asset_id = 1 AND status = \'ACTIVE\'', [project.recipient_account_id])).rows[0];
      if (!escrow || !earth || !destination || BigInt(earth.balance_units) < match) throw new Error('Public matching pool cash is unavailable');
      const entries: Array<{ account_id: string; asset_id: number; delta_units: string }> = [{ account_id: escrow.id, asset_id: 1, delta_units: (-contributed).toString() }];
      if (match > 0n) entries.push({ account_id: earth.id, asset_id: 1, delta_units: (-match).toString() });
      entries.push({ account_id: destination.id, asset_id: 1, delta_units: (contributed + match).toString() });
      const posted = await tx.query<{ transaction_id: string }>('SELECT transaction_id FROM earth_post_transaction($1,$2,0,\'PUBLIC_PROJECT_SETTLEMENT\',\'EARTH\',\'EARTH\',\'public-projects-v1\',$3::JSONB)', [`public-project:${projectId}:${gameDay}`, gameDay, JSON.stringify(entries)]);
      settlementTransactionId = posted.rows[0]?.transaction_id ?? null;
      await tx.query("UPDATE public_project_contributions SET status = 'RELEASED' WHERE project_id = $1 AND status = 'ESCROWED'", [projectId]);
    } else if (!funded && contributed > 0n) {
      const refunds = await tx.query<{ id: string; amount_units: string; escrow_account_id: string; wallet_id: string }>(`SELECT c.id, c.amount_units::TEXT, c.escrow_account_id::TEXT, w.id::TEXT AS wallet_id FROM public_project_contributions c JOIN economic_accounts w ON w.owner_economic_id = (SELECT economic_id FROM owner_registry WHERE id = c.house_id AND owner_type = 'HOUSE') AND w.asset_id = 1 AND w.account_type = 'WALLET' AND w.status = 'ACTIVE' WHERE c.project_id = $1 AND c.status = 'ESCROWED' FOR UPDATE`, [projectId]);
      for (const refund of refunds.rows) await tx.query('SELECT earth_post_transaction($1,$2,0,\'PUBLIC_PROJECT_REFUND\',\'EARTH\',\'EARTH\',\'public-projects-v1\',$3::JSONB)', [`public-project-refund:${refund.id}`, gameDay, JSON.stringify([{ account_id: refund.escrow_account_id, asset_id: 1, delta_units: (-BigInt(refund.amount_units)).toString() }, { account_id: refund.wallet_id, asset_id: 1, delta_units: refund.amount_units }])]);
      await tx.query("UPDATE public_project_contributions SET status = 'REFUNDED' WHERE project_id = $1 AND status = 'ESCROWED'", [projectId]);
    }
    await tx.query("UPDATE public_projects SET matched_units = $1, matching_pool_spent_units = matching_pool_spent_units + $1, status = $2 WHERE id = $3", [match.toString(), funded ? 'SETTLED' : 'FAILED', projectId]);
    await tx.query(`INSERT INTO public_project_settlements (id, project_id, contributed_units, matched_units, supporter_count, settlement_transaction_id, settled_game_day, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`, [`SETTLE-${projectId}`, projectId, contributed.toString(), match.toString(), supporters.rows[0]?.count ?? '0', settlementTransactionId, gameDay, `settle:${projectId}:${gameDay}`]);
    await createGameEvent(tx, { id: `PUBLIC-PROJECT-SETTLED-${projectId}`, category: 'GOVERNANCE', eventType: 'PUBLIC_PROJECT_SETTLED', gameDay, actorHumanId: null, subjectType: 'EARTH', subjectId: 'EARTH', title: funded ? 'Public project funded' : 'Public project refunded', details: { projectId, contributedUnits: contributed.toString(), matchedUnits: match.toString(), supporterCount: supporters.rows[0]?.count ?? '0', status: funded ? 'SETTLED' : 'FAILED' }, correlationId: `settle:${projectId}:${gameDay}` });
    return { ok: true, projectId, status: funded ? 'SETTLED' : 'FAILED', contributedUnits: contributed.toString(), matchedUnits: match.toString(), supporterCount: supporters.rows[0]?.count ?? '0' };
}

export async function settlePublicProject(repository: PostgresRepository, projectId: string, gameDay: number): Promise<Record<string, unknown>> {
  return repository.transaction((tx) => settlePublicProjectInTransaction(tx, projectId, gameDay));
}

export async function settleDuePublicProjectsInTransaction(tx: PostgresRepository, gameDay: number): Promise<Record<string, unknown>> {
  const due = await tx.query<{ id: string }>("SELECT id FROM public_projects WHERE status IN ('OPEN','FUNDED') AND deadline_game_day <= $1 ORDER BY deadline_game_day, id LIMIT 100 FOR UPDATE SKIP LOCKED", [gameDay]);
  let settled = 0;
  for (const project of due.rows) { await settlePublicProjectInTransaction(tx, project.id, gameDay); settled += 1; }
  return { ok: true, gameDay, settled };
}
