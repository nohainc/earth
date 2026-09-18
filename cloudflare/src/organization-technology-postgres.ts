import type { PostgresRepository } from './repository.ts';
import { createGameEvent } from './game-events-postgres.ts';
import { resolveOrganizationAuthority } from './organization-authority.ts';
import { assertEarthTechnologyFrontier, getEarthTechnologyFrontier } from './earth-technology-frontier-postgres.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';
import { runEconomicMutation } from './settlement-barrier-postgres.ts';
import { postEconomicTransaction } from './economic-transaction-postgres.ts';

export async function listOrganizationTechnologyAdoptions(repository: PostgresRepository, organizationId: string, houseId: string): Promise<Record<string, unknown>> {
  const access = await repository.query('SELECT 1 FROM organization_memberships WHERE organization_id = $1 AND house_id = $2 AND status = \'ACTIVE\'', [organizationId, houseId]);
  if (!access.rows[0]) throw new Error('Organization membership required');
  const [adoptions, proposals] = await Promise.all([
    repository.query(`SELECT a.id, a.organization_id, a.generation_id, g.name AS generation_name, a.status, a.adoption_cost_units::TEXT, a.adopted_game_day, a.effective_from_game_day, a.authorization_proposal_id, a.rules_version FROM organization_technology_adoptions a JOIN technology_generations g ON g.id = a.generation_id WHERE a.organization_id = $1 ORDER BY a.created_at DESC, a.id`, [organizationId]),
    repository.query(`SELECT id, title, body, action_snapshot, status, voting_start_game_day, voting_end_game_day, support_votes, oppose_votes, created_by_human_id FROM governance_proposals_v4 WHERE subject_type = 'ORGANIZATION' AND subject_id = $1 AND action_type = 'ORGANIZATION_TECHNOLOGY_ADOPTION' ORDER BY created_at DESC, id`, [organizationId]),
  ]);
  const frontier = await getEarthTechnologyFrontier(repository);
  return { organizationId, adoptions: adoptions.rows, adoptionProposals: proposals.rows, earthFrontier: frontier.frontier, generatedFrom: 'postgres-canonical-facts' };
}

export async function proposeTechnologyAdoption(repository: PostgresRepository, input: { organizationId: string; generationId: string; humanId: string; correlationId: string }): Promise<Record<string, unknown>> {
  const generation = (await repository.query<{ name: string; research_points_required: string; domain_id: string; generation_number: number }>('SELECT name, research_points_required::TEXT, domain_id, generation_number FROM technology_generations WHERE id = $1 AND status <> \'RETIRED\'', [input.generationId])).rows[0];
  if (!generation) throw new Error('Technology generation not found');
  const day = (await readAuthoritativeGameTime(repository)).gameDay;
  await assertEarthTechnologyFrontier(repository, generation.domain_id, Number(generation.generation_number), day);
  const cost = (BigInt(generation.research_points_required) * 100n).toString();
  const { createGovernanceProposalV4 } = await import('./governance-v4-postgres.ts');
  return createGovernanceProposalV4(repository, { humanId: input.humanId, subjectType: 'ORGANIZATION', subjectId: input.organizationId, title: `Adopt ${generation.name}`, body: `Authorize ${cost} CREDIT for Organization adoption of ${generation.name}.`, actionType: 'ORGANIZATION_TECHNOLOGY_ADOPTION', actionSnapshot: { generationId: input.generationId, adoptionCostUnits: cost }, correlationId: input.correlationId });
}

export async function retireTechnologyAdoption(repository: PostgresRepository, input: { organizationId: string; adoptionId: string; humanId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ id: string }>('SELECT id FROM organization_technology_adoptions WHERE correlation_id = $1', [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, adoptionId: prior.rows[0].id, correlationId: input.correlationId };
    await resolveOrganizationAuthority(tx, { organizationId: input.organizationId, humanId: input.humanId, action: 'RESEARCH' });
    const row = (await tx.query<{ id: string; status: string; generation_id: string }>('SELECT id, status, generation_id FROM organization_technology_adoptions WHERE id = $1 AND organization_id = $2 FOR UPDATE', [input.adoptionId, input.organizationId])).rows[0];
    if (!row || row.status !== 'ADOPTED') throw new Error('Only an active adopted technology can be retired');
    const day = (await readAuthoritativeGameTime(tx)).gameDay;
    await tx.query("UPDATE organization_technology_adoptions SET status = 'RETIRED' WHERE id = $1", [row.id]);
    await createGameEvent(tx, { id: `ORG-TECH-RETIRED-${row.id}-${input.correlationId}`, category: 'RESEARCH', eventType: 'ORGANIZATION_TECHNOLOGY_RETIRED', gameDay: day, actorHumanId: input.humanId, subjectType: 'ORGANIZATION', subjectId: input.organizationId, title: 'Organization technology retired', details: { adoptionId: row.id, generationId: row.generation_id }, correlationId: input.correlationId });
    return { ok: true, adoptionId: row.id, status: 'RETIRED', correlationId: input.correlationId };
  });
}

export async function adoptTechnologyGeneration(repository: PostgresRepository, input: { organizationId: string; generationId: string; proposalId: string; humanId: string; houseId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return runEconomicMutation(repository, async (tx, clock) => {
    const prior = await tx.query<{ id: string }>('SELECT id FROM organization_technology_adoptions WHERE correlation_id = $1', [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, adoptionId: prior.rows[0].id, correlationId: input.correlationId };
    await resolveOrganizationAuthority(tx, { organizationId: input.organizationId, humanId: input.humanId, action: 'RESEARCH' });
    const proposal = (await tx.query<{ status: string; subject_type: string; subject_id: string | null }>('SELECT status, subject_type, subject_id FROM governance_proposals_v4 WHERE id = $1', [input.proposalId])).rows[0];
    if (!proposal || proposal.status !== 'PASSED' || proposal.subject_type !== 'ORGANIZATION' || proposal.subject_id !== input.organizationId) throw new Error('Technology adoption requires a passed Organization proposal');
    const generation = (await tx.query<{ id: string; name: string; research_points_required: string; minimum_game_day: number; predecessor_id: string | null; domain_id: string; generation_number: number }>('SELECT id, name, research_points_required::TEXT, minimum_game_day, predecessor_id, domain_id, generation_number FROM technology_generations WHERE id = $1 AND status <> \'RETIRED\'', [input.generationId])).rows[0];
    if (!generation) throw new Error('Technology generation not found');
    const day = clock.gameDay;
    await assertEarthTechnologyFrontier(tx, generation.domain_id, Number(generation.generation_number), day);
    const discovery = (await tx.query<{ effective_from_game_day: number }>('SELECT effective_from_game_day FROM technology_discoveries WHERE generation_id = $1', [input.generationId])).rows[0];
    if (!discovery || Number(discovery.effective_from_game_day) > day) throw new Error('Technology generation is not yet effective');
    const duplicate = await tx.query('SELECT 1 FROM organization_technology_adoptions WHERE organization_id = $1 AND generation_id = $2 AND status IN (\'PROPOSED\',\'ADOPTED\')', [input.organizationId, input.generationId]);
    if (duplicate.rows[0]) throw new Error('Organization already adopted or is adopting this generation');
    const cost = BigInt(generation.research_points_required) * 100n;
    const account = (await tx.query<{ id: string; balance_units: string }>(`SELECT a.id::TEXT, a.balance_units::TEXT FROM economic_accounts a JOIN organization_economies e ON e.economic_id = a.owner_economic_id WHERE e.organization_id = $1 AND a.account_type = 'OPERATIONS' AND a.asset_id = 1 AND a.status = 'ACTIVE' FOR UPDATE`, [input.organizationId])).rows[0];
    const system = (await tx.query<{ id: string }>(`SELECT a.id::TEXT FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.id = 'SYSTEM' AND a.account_type = 'SYSTEM_ACCOUNT' AND a.asset_id = 1 AND a.status = 'ACTIVE' LIMIT 1`)).rows[0];
    if (!account || !system || BigInt(account.balance_units) < cost) throw new Error('Organization research treasury is insufficient');
    const posted = await postEconomicTransaction(tx, {
      correlationId: input.correlationId,
      kind: 'TECHNOLOGY_ADOPTION',
      sourceType: 'ORGANIZATION',
      sourceId: input.organizationId,
      rulesVersion: 'technology-adoption-v1',
      entries: [
        { accountId: account.id, assetId: 1, deltaUnits: (-cost).toString() },
        { accountId: system.id, assetId: 1, deltaUnits: cost.toString() },
      ],
    }, clock);
    const adoptionId = `ADOPTION-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    await tx.query(`INSERT INTO organization_technology_adoptions (id, organization_id, generation_id, authorization_proposal_id, status, adoption_cost_units, adopted_game_day, effective_from_game_day, rules_version, correlation_id, created_by_human_id) VALUES ($1,$2,$3,$4,'ADOPTED',$5,$6,$7,'technology-adoption-v1',$8,$9)`, [adoptionId, input.organizationId, input.generationId, input.proposalId, cost.toString(), day, day + 1, input.correlationId, input.humanId]);
    await createGameEvent(tx, { id: `ORG-TECH-ADOPTED-${adoptionId}`, category: 'RESEARCH', eventType: 'ORGANIZATION_TECHNOLOGY_ADOPTED', gameDay: day, actorHumanId: input.humanId, subjectType: 'ORGANIZATION', subjectId: input.organizationId, title: `${generation.name} adopted`, details: { generationId: input.generationId, costUnits: cost.toString(), proposalId: input.proposalId, transactionId: posted.transactionId }, correlationId: input.correlationId });
    return { ok: true, adoptionId, organizationId: input.organizationId, generationId: input.generationId, status: 'ADOPTED', effectiveFromGameDay: day + 1, costUnits: cost.toString(), correlationId: input.correlationId };
  });
}
