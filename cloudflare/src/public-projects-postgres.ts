import type { PostgresRepository } from './repository.ts';
import { createGameEvent } from './game-events-postgres.ts';
import { calculateMatching } from './public-projects.ts';
import { runEconomicMutation } from './settlement-barrier-postgres.ts';
import { postEconomicTransaction, postSettlementTransaction } from './economic-transaction-postgres.ts';

export async function listPublicProjects(repository: PostgresRepository): Promise<Record<string, unknown>> {
  const projects = await repository.query(`SELECT p.id, p.name, p.description, p.beneficiary_type, p.beneficiary_id, p.target_units::TEXT, p.deadline_game_day, p.matching_pool_authorized_units::TEXT, p.matching_pool_funded_units::TEXT, p.contribution_units::TEXT, p.matched_units::TEXT, p.status, p.created_game_day, COUNT(c.id)::INTEGER AS supporter_count FROM public_projects p LEFT JOIN public_project_contributions c ON c.project_id = p.id AND c.status = 'ESCROWED' GROUP BY p.id ORDER BY p.status, p.deadline_game_day, p.id`);
  return {
    projects: projects.rows.map((project) => ({
      ...project,
      capabilities: {
        canContribute: ['OPEN', 'FUNDED'].includes(String(project.status).toUpperCase()),
        // Matching and settlement are governance/treasury operations. They
        // must not be inferred from a public status alone.
        canFundMatching: false,
        canSettle: false,
      },
    })),
    generatedFrom: 'postgres-canonical-facts',
  };
}

export async function getPublicProject(repository: PostgresRepository, projectId: string): Promise<Record<string, unknown>> {
  const result = await repository.query<any>(`SELECT p.*, COUNT(DISTINCT c.house_id)::INTEGER AS supporter_count FROM public_projects p LEFT JOIN public_project_contributions c ON c.project_id = p.id AND c.status = 'ESCROWED' WHERE p.id = $1 GROUP BY p.id`, [projectId]);
  const project = result.rows[0];
  if (!project) throw new Error('Public project not found');
  const match = calculateMatching({ contributionUnits: BigInt(project.contribution_units), supporterCount: BigInt(project.supporter_count), poolRemaining: BigInt(project.matching_pool_funded_units) - BigInt(project.matching_pool_spent_units), targetRemaining: BigInt(project.target_units) > BigInt(project.contribution_units) ? BigInt(project.target_units) - BigInt(project.contribution_units) : 0n, matchBps: 10000n });
  const { recipient_account_id: _recipientAccountId, proposal_id: _proposalId, created_by_human_id: _createdByHumanId, ...playerProject } = project;
  return {
    project: {
      ...playerProject,
      projected_match_units: match.toString(),
      capabilities: {
        canContribute: ['OPEN', 'FUNDED'].includes(String(project.status).toUpperCase()),
        canFundMatching: false,
        canSettle: false,
      },
    },
    generatedFrom: 'postgres-canonical-facts',
  };
}

export async function contributeToPublicProject(repository: PostgresRepository, input: { projectId: string; houseId: string; amountUnits: string; humanId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return runEconomicMutation(repository, async (tx, clock) => {
    const prior = await tx.query<{ id: string }>('SELECT id FROM public_project_contributions WHERE correlation_id = $1', [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, contributionId: prior.rows[0].id, correlationId: input.correlationId };
    const project = (await tx.query<{ recipient_account_id: string; deadline_game_day: number; status: string; target_units: string; contribution_units: string }>('SELECT recipient_account_id::TEXT, deadline_game_day, status, target_units::TEXT, contribution_units::TEXT FROM public_projects WHERE id = $1 FOR UPDATE', [input.projectId])).rows[0];
    const amount = BigInt(input.amountUnits);
    if (!project || !['OPEN', 'FUNDED'].includes(project.status) || amount <= 0n) throw new Error('Public project is not accepting contributions');
    const current = clock.gameDay;
    if (current > Number(project.deadline_game_day)) throw new Error('Public project deadline has passed');
    if (BigInt(project.contribution_units) + amount > BigInt(project.target_units)) throw new Error('Contribution exceeds project target');
    const source = (await tx.query<{ id: string; balance_units: string }>('SELECT a.id::TEXT, a.balance_units::TEXT FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.id = $1 AND o.owner_type = \'HOUSE\' AND a.asset_id = 1 AND a.account_type = \'WALLET\' AND a.status = \'ACTIVE\' FOR UPDATE', [input.houseId])).rows[0];
    const escrow = (await tx.query<{ id: string }>('SELECT id::TEXT FROM economic_accounts WHERE owner_economic_id = (SELECT economic_id FROM owner_registry WHERE id = \'ECON-CONSTRUCTION-SETTLEMENT\') AND asset_id = 1 AND account_type = \'SYSTEM_ACCOUNT\' AND status = \'ACTIVE\' LIMIT 1')).rows[0];
    if (!source || !escrow || BigInt(source.balance_units) < amount) throw new Error('Contribution wallet balance or project escrow is unavailable');
    const posted = await postEconomicTransaction(tx, {
      correlationId: input.correlationId,
      kind: 'PUBLIC_PROJECT_CONTRIBUTION',
      sourceType: 'HOUSE',
      sourceId: input.houseId,
      rulesVersion: 'public-projects-v1',
      entries: [
        { accountId: source.id, assetId: 1, deltaUnits: (-amount).toString() },
        { accountId: escrow.id, assetId: 1, deltaUnits: amount.toString() },
      ],
    }, clock);
    if (!posted.created) return { ok: true, alreadyProcessed: true, correlationId: input.correlationId };
    const contributionId = `CONTRIB-${input.correlationId}`;
    await tx.query(`INSERT INTO public_project_contributions (id, project_id, house_id, amount_units, escrow_account_id, contribution_transaction_id, correlation_id, created_game_day) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`, [contributionId, input.projectId, input.houseId, amount.toString(), escrow.id, posted.transactionId, input.correlationId, current]);
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
      const entries: Array<{ accountId: string; assetId: number; deltaUnits: string }> = [{ accountId: escrow.id, assetId: 1, deltaUnits: (-contributed).toString() }];
      if (match > 0n) entries.push({ accountId: earth.id, assetId: 1, deltaUnits: (-match).toString() });
      entries.push({ accountId: destination.id, assetId: 1, deltaUnits: (contributed + match).toString() });
      const posted = await postSettlementTransaction(tx, {
        correlationId: `public-project:${projectId}:${gameDay}`,
        gameDay,
        kind: 'PUBLIC_PROJECT_SETTLEMENT',
        sourceType: 'EARTH',
        sourceId: 'EARTH',
        rulesVersion: 'public-projects-v1',
        entries,
      });
      settlementTransactionId = posted.transactionId ?? null;
      await tx.query("UPDATE public_project_contributions SET status = 'RELEASED' WHERE project_id = $1 AND status = 'ESCROWED'", [projectId]);
    } else if (!funded && contributed > 0n) {
      const refunds = await tx.query<{ id: string; amount_units: string; escrow_account_id: string; wallet_id: string }>(`SELECT c.id, c.amount_units::TEXT, c.escrow_account_id::TEXT, w.id::TEXT AS wallet_id FROM public_project_contributions c JOIN economic_accounts w ON w.owner_economic_id = (SELECT economic_id FROM owner_registry WHERE id = c.house_id AND owner_type = 'HOUSE') AND w.asset_id = 1 AND w.account_type = 'WALLET' AND w.status = 'ACTIVE' WHERE c.project_id = $1 AND c.status = 'ESCROWED' FOR UPDATE`, [projectId]);
      for (const refund of refunds.rows) {
        await postSettlementTransaction(tx, {
          correlationId: `public-project-refund:${refund.id}`,
          gameDay,
          kind: 'PUBLIC_PROJECT_REFUND',
          sourceType: 'EARTH',
          sourceId: 'EARTH',
          rulesVersion: 'public-projects-v1',
          entries: [
            { accountId: refund.escrow_account_id, assetId: 1, deltaUnits: (-BigInt(refund.amount_units)).toString() },
            { accountId: refund.wallet_id, assetId: 1, deltaUnits: refund.amount_units },
          ],
        });
      }
      await tx.query("UPDATE public_project_contributions SET status = 'REFUNDED' WHERE project_id = $1 AND status = 'ESCROWED'", [projectId]);
    }
    // A failed project receives no match. Keep the authorized pool available
    // for later projects instead of consuming a hypothetical calculation.
    const spentMatch = funded ? match : 0n;
    await tx.query("UPDATE public_projects SET matched_units = $1, matching_pool_spent_units = matching_pool_spent_units + $2, status = $3 WHERE id = $4", [funded ? match.toString() : '0', spentMatch.toString(), funded ? 'SETTLED' : 'FAILED', projectId]);
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
