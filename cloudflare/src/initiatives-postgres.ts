import type { PostgresRepository } from './repository.ts';
import { runEconomicMutation } from './settlement-barrier-postgres.ts';
import { postEconomicTransaction, postSettlementTransaction } from './economic-transaction-postgres.ts';
import { calculateMatching, type InitiativeMatchingPolicy } from './public-projects.ts';
import { applyInitiativeOutcome, validateInitiativeOutcome } from './initiative-outcomes.ts';
import { createGameEvent } from './game-events-postgres.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';

export async function listInitiatives(repository: PostgresRepository, houseId?: string, filters: { status?: string; scope?: 'EARTH' | 'CORPORATION'; mySupport?: boolean } = {}): Promise<Record<string, unknown>> {
  const where: string[] = [];
  const params: unknown[] = [];
  if (filters.status && ['FUNDING', 'EXECUTING', 'COMPLETED', 'FAILED', 'CANCELLED'].includes(filters.status)) { params.push(filters.status); where.push(`i.status = $${params.length}`); }
  if (filters.scope && ['EARTH', 'CORPORATION'].includes(filters.scope)) { params.push(filters.scope); where.push(`i.scope_type = $${params.length}`); }
  if (filters.mySupport && houseId) { params.push(houseId); where.push(`EXISTS (SELECT 1 FROM initiative_contributions viewer_support WHERE viewer_support.initiative_id = i.id AND viewer_support.house_id = $${params.length} AND viewer_support.status IN ('ESCROWED','APPLIED'))`); }
  const viewerParam = houseId ? (params.push(houseId), `$${params.length}`) : null;
  const initiatives = await repository.query(`
    SELECT i.id, i.scope_type, i.scope_id, i.initiative_type, i.name, i.description,
           i.funding_target_units::TEXT, i.treasury_authorized_units::TEXT,
           i.matching_policy, i.matching_cap_units::TEXT, i.funding_deadline_game_day,
           i.funding_model, i.execution_model, i.outcome, i.physical_target,
           i.status, i.effective_game_day, i.created_game_day,
           e.execution_model, e.status AS execution_status, e.progress_model,
           e.progress_bps, e.required_duration_game_days,
           e.required_resource_requirements, e.consumed_resource_requirements,
           e.started_game_day, e.completed_game_day, e.blocked_reason,
           COALESCE(SUM(c.amount_units) FILTER (WHERE c.status IN ('ESCROWED','APPLIED')), 0)::TEXT AS community_contribution_units,
           COALESCE(SUM(c.matching_units) FILTER (WHERE c.status IN ('ESCROWED','APPLIED')), 0)::TEXT AS matching_applied_units,
           COUNT(DISTINCT c.house_id) FILTER (WHERE c.status IN ('ESCROWED','APPLIED'))::INTEGER AS supporter_count,
           ${viewerParam ? `COALESCE(SUM(c.amount_units) FILTER (WHERE c.house_id = ${viewerParam} AND c.status IN ('ESCROWED','APPLIED')), 0)::TEXT` : "'0'"} AS viewer_contribution_units,
           COALESCE((SELECT jsonb_agg(jsonb_build_object(
             'commitmentType', fc.commitment_type,
             'sourceType', fc.source_type,
             'authorizedUnits', fc.authorized_units::TEXT,
             'committedUnits', fc.committed_units::TEXT,
             'status', fc.status
           ) ORDER BY fc.commitment_type) FROM initiative_funding_commitments fc WHERE fc.initiative_id = i.id), '[]'::JSONB) AS funding_commitments
      FROM v5_initiatives i
      LEFT JOIN initiative_executions e ON e.initiative_id = i.id
      LEFT JOIN initiative_contributions c ON c.initiative_id = i.id
     GROUP BY i.id, e.execution_model, e.status, e.progress_model, e.progress_bps,
              e.required_duration_game_days, e.required_resource_requirements,
              e.consumed_resource_requirements, e.started_game_day,
              e.completed_game_day, e.blocked_reason
     ${where.length ? `HAVING ${where.join(' AND ')}` : ''}
     ORDER BY i.status, i.funding_deadline_game_day, i.id`, params);
  const rows = initiatives.rows.map((row: Record<string, unknown>) => {
    const target = BigInt(String(row.funding_target_units ?? '0'));
    const community = BigInt(String(row.community_contribution_units ?? '0'));
    const matching = BigInt(String(row.matching_applied_units ?? '0'));
    const commitments = Array.isArray(row.funding_commitments) ? row.funding_commitments as Array<Record<string, unknown>> : [];
    const committedTreasury = commitments.filter((item) => item.commitmentType === 'TREASURY').reduce((sum, item) => sum + BigInt(String(item.committedUnits ?? '0')), 0n);
    const funded = community + matching + committedTreasury;
    return {
      id: row.id, scope: { type: row.scope_type, id: row.scope_id }, type: row.initiative_type,
      name: row.name, description: row.description, status: row.status,
      fundingTargetUnits: String(row.funding_target_units ?? '0'), communityContributionUnits: String(row.community_contribution_units ?? '0'),
      matchCommittedUnits: commitments.filter((item) => item.commitmentType === 'MATCHING').reduce((sum, item) => sum + BigInt(String(item.committedUnits ?? '0')), 0n).toString(),
      matchAppliedUnits: String(row.matching_applied_units ?? '0'), treasuryCommittedUnits: committedTreasury.toString(),
      fundingProgressBps: target > 0n ? Number(((funded * 10000n / target) > 10000n) ? 10000n : (funded * 10000n / target)) : 0,
      supporterCount: Number(row.supporter_count ?? 0), deadlineGameDay: row.funding_deadline_game_day,
      houseContributionUnits: String(row.viewer_contribution_units ?? '0'),
      outcomePreview: row.outcome, execution: { model: row.execution_model, status: row.execution_status, progressModel: row.progress_model, progressBps: row.progress_bps, durationGameDays: row.required_duration_game_days, requiredResources: row.required_resource_requirements, consumedResources: row.consumed_resource_requirements, startedGameDay: row.started_game_day, completedGameDay: row.completed_game_day, blockedReason: row.blocked_reason },
      capabilities: { canContribute: row.status === 'FUNDING', viewerHasSupport: BigInt(String(row.viewer_contribution_units ?? '0')) > 0n, canManageFunding: false, canSettle: false },
    };
  });
  return { initiatives: rows, summary: { activeCount: rows.filter((row) => ['FUNDING', 'EXECUTING'].includes(String(row.status))).length, fundingCount: rows.filter((row) => row.status === 'FUNDING').length, completedCount: rows.filter((row) => row.status === 'COMPLETED').length, communityCapitalUnits: rows.reduce((sum, row) => sum + BigInt(String(row.communityContributionUnits)), 0n).toString(), supportingInitiativesCount: rows.filter((row) => (row.capabilities as Record<string, unknown>).viewerHasSupport === true).length }, generatedFrom: 'v5-initiative-canonical-read-model-v1' };
}

export async function contributeToInitiative(repository: PostgresRepository, input: { initiativeId: string; houseId: string; amountUnits: string; correlationId: string }): Promise<Record<string, unknown>> {
  return runEconomicMutation(repository, async (tx, clock) => {
    const prior = (await tx.query<{ id: string }>('SELECT id FROM initiative_contributions WHERE correlation_id = $1', [input.correlationId])).rows[0];
    if (prior) return { ok: true, alreadyProcessed: true, contributionId: prior.id, correlationId: input.correlationId };
    const initiative = (await tx.query<{ id: string; funding_target_units: string; funding_deadline_game_day: number; matching_policy: InitiativeMatchingPolicy; matching_cap_units: string; status: string; funding_policy_id: string }>(
      `SELECT id, funding_target_units::TEXT, funding_deadline_game_day, matching_policy, matching_cap_units::TEXT, status, funding_policy_id
         FROM v5_initiatives WHERE id = $1 FOR UPDATE`, [input.initiativeId])).rows[0];
    if (!initiative || !['FUNDING', 'FUNDED'].includes(initiative.status)) throw new Error('Initiative is not accepting contributions');
    if (clock.gameDay > Number(initiative.funding_deadline_game_day)) throw new Error('Initiative funding deadline has passed');
    const amount = BigInt(input.amountUnits);
    if (amount <= 0n) throw new Error('Contribution must be positive');
    const source = (await tx.query<{ id: string; balance_units: string }>(`SELECT a.id::TEXT, a.balance_units::TEXT FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.id = $1 AND o.owner_type = 'HOUSE' AND a.asset_id = 1 AND a.account_type = 'WALLET' AND a.status = 'ACTIVE' FOR UPDATE`, [input.houseId])).rows[0];
    const escrow = (await tx.query<{ id: string }>(`SELECT id::TEXT FROM economic_accounts WHERE owner_economic_id = (SELECT economic_id FROM owner_registry WHERE id = 'ECON-CONSTRUCTION-SETTLEMENT') AND asset_id = 1 AND account_type = 'SYSTEM_ACCOUNT' AND status = 'ACTIVE' LIMIT 1`)).rows[0];
    if (!source || !escrow || BigInt(source.balance_units) < amount) throw new Error('House wallet balance or Initiative escrow is unavailable');
    const totals = (await tx.query<{ amount: string; supporters: string }>(`SELECT COALESCE(SUM(amount_units),0)::TEXT AS amount, COUNT(DISTINCT house_id)::TEXT AS supporters FROM initiative_contributions WHERE initiative_id = $1 AND status IN ('ESCROWED','APPLIED')`, [input.initiativeId])).rows[0];
    const remaining = BigInt(initiative.funding_target_units) > BigInt(totals?.amount ?? '0') ? BigInt(initiative.funding_target_units) - BigInt(totals?.amount ?? '0') : 0n;
    if (amount > remaining) throw new Error('Contribution exceeds Initiative funding target');
    const policy = (await tx.query<{ match_rate_bps: string; breadth_bonus_bps_per_supporter: string; breadth_supporter_cap: string; max_house_contribution_units: string }>(`SELECT match_rate_bps::TEXT, breadth_bonus_bps_per_supporter::TEXT, breadth_supporter_cap::TEXT, max_house_contribution_units::TEXT FROM initiative_funding_policies WHERE id = $1 AND status = 'ACTIVE'`, [initiative.funding_policy_id])).rows[0];
    if (!policy) throw new Error('Initiative funding policy is unavailable');
    const dailyContribution = (await tx.query<{ total: string }>(`SELECT COALESCE(SUM(amount_units),0)::TEXT AS total FROM initiative_contributions WHERE initiative_id = $1 AND house_id = $2 AND created_game_day = $3 AND status = 'ESCROWED'`, [input.initiativeId, input.houseId, clock.gameDay])).rows[0];
    if (BigInt(dailyContribution?.total ?? '0') + amount > BigInt(policy.max_house_contribution_units)) throw new Error('House Initiative contribution limit exceeded');
    const matching = initiative.matching_policy === 'NONE'
      ? 0n
      : calculateMatching({ contributionUnits: amount, supporterCount: BigInt(totals?.supporters ?? '0') + 1n, poolRemaining: BigInt(initiative.matching_cap_units), targetRemaining: remaining, matchBps: BigInt(policy.match_rate_bps), policy: initiative.matching_policy, breadthBonusBpsPerSupporter: BigInt(policy.breadth_bonus_bps_per_supporter), breadthSupporterCap: BigInt(policy.breadth_supporter_cap) });
    const posted = await postEconomicTransaction(tx, { correlationId: input.correlationId, kind: 'INITIATIVE_CONTRIBUTION', sourceType: 'HOUSE', sourceId: input.houseId, rulesVersion: 'v5-initiative-v1', entries: [{ accountId: source.id, assetId: 1, deltaUnits: (-amount).toString() }, { accountId: escrow.id, assetId: 1, deltaUnits: amount.toString() }] }, clock);
    if (!posted.created) return { ok: true, alreadyProcessed: true, correlationId: input.correlationId };
    const contributionId = `INIT-CONTRIB-${input.correlationId}`;
    await tx.query(`INSERT INTO initiative_contributions (id, initiative_id, house_id, amount_units, matching_units, escrow_account_id, contribution_transaction_id, status, created_game_day, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,'ESCROWED',$8,$9)`, [contributionId, input.initiativeId, input.houseId, amount.toString(), matching.toString(), escrow.id, posted.transactionId, clock.gameDay, input.correlationId]);
    await createGameEvent(tx, { id: `INITIATIVE-CONTRIBUTION-${contributionId}`, category: 'INITIATIVE', eventType: 'INITIATIVE_CONTRIBUTION_ESCROWED', gameDay: clock.gameDay, actorHouseId: input.houseId, subjectType: 'INITIATIVE', subjectId: input.initiativeId, title: 'House contribution escrowed for Initiative', details: { initiativeId: input.initiativeId, contributionUnits: amount.toString(), projectedMatchingUnits: matching.toString(), transactionId: posted.transactionId }, correlationId: `initiative-contribution-event:${input.correlationId}` });
    return { ok: true, contributionId, initiativeId: input.initiativeId, amountUnits: amount.toString(), estimatedMatchingUnits: matching.toString(), transactionId: posted.transactionId, correlationId: input.correlationId };
  });
}

export async function quoteInitiativeContribution(repository: PostgresRepository, input: { initiativeId: string; houseId: string; amountUnits: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const clock = await readAuthoritativeGameTime(tx);
    const amount = BigInt(input.amountUnits);
    if (amount <= 0n) throw new Error('Contribution must be positive');
    const initiative = (await tx.query<{ id: string; name: string; funding_target_units: string; funding_deadline_game_day: number; matching_policy: InitiativeMatchingPolicy; matching_cap_units: string; funding_policy_id: string; status: string }>(`SELECT id, name, funding_target_units::TEXT, funding_deadline_game_day, matching_policy, matching_cap_units::TEXT, funding_policy_id, status FROM v5_initiatives WHERE id = $1`, [input.initiativeId])).rows[0];
    if (!initiative || initiative.status !== 'FUNDING') throw new Error('Initiative is not accepting contributions');
    if (clock.gameDay > Number(initiative.funding_deadline_game_day)) throw new Error('Initiative funding deadline has passed');
    const wallet = (await tx.query<{ balance_units: string }>(`SELECT a.balance_units::TEXT FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.id = $1 AND o.owner_type = 'HOUSE' AND a.asset_id = 1 AND a.account_type = 'WALLET' AND a.status = 'ACTIVE'`, [input.houseId])).rows[0];
    if (!wallet || BigInt(wallet.balance_units) < amount) throw new Error('House wallet balance is insufficient');
    const totals = (await tx.query<{ contributed: string; supporters: string }>(`SELECT COALESCE(SUM(amount_units),0)::TEXT AS contributed, COUNT(DISTINCT house_id)::TEXT AS supporters FROM initiative_contributions WHERE initiative_id = $1 AND status IN ('ESCROWED','APPLIED')`, [input.initiativeId])).rows[0];
    const existingContribution = BigInt(totals?.contributed ?? '0');
    const remainingBefore = BigInt(initiative.funding_target_units) > existingContribution ? BigInt(initiative.funding_target_units) - existingContribution : 0n;
    if (amount > remainingBefore) throw new Error('Contribution exceeds remaining community funding requirement');
    const policy = (await tx.query<{ match_rate_bps: string; breadth_bonus_bps_per_supporter: string; breadth_supporter_cap: string; max_house_contribution_units: string }>(`SELECT match_rate_bps::TEXT, breadth_bonus_bps_per_supporter::TEXT, breadth_supporter_cap::TEXT, max_house_contribution_units::TEXT FROM initiative_funding_policies WHERE id = $1 AND status = 'ACTIVE'`, [initiative.funding_policy_id])).rows[0];
    if (!policy) throw new Error('Initiative funding policy is unavailable');
    if (amount > BigInt(policy.max_house_contribution_units)) throw new Error('Contribution exceeds the House contribution limit');
    const projectedMatching = initiative.matching_policy === 'NONE' ? 0n : calculateMatching({ contributionUnits: amount, supporterCount: BigInt(totals?.supporters ?? '0') + 1n, poolRemaining: BigInt(initiative.matching_cap_units), targetRemaining: remainingBefore, matchBps: BigInt(policy.match_rate_bps), policy: initiative.matching_policy, breadthBonusBpsPerSupporter: BigInt(policy.breadth_bonus_bps_per_supporter), breadthSupporterCap: BigInt(policy.breadth_supporter_cap) });
    const remainingAfter = BigInt(initiative.funding_target_units) > existingContribution + amount + projectedMatching ? BigInt(initiative.funding_target_units) - existingContribution - amount - projectedMatching : 0n;
    return { initiativeId: initiative.id, initiativeName: initiative.name, gameDay: clock.gameDay, walletBeforeUnits: wallet.balance_units, walletAfterUnits: (BigInt(wallet.balance_units) - amount).toString(), contributionUnits: amount.toString(), projectedMatchingUnits: projectedMatching.toString(), remainingFundingRequirementUnits: remainingAfter.toString(), existingCommunityContributionUnits: existingContribution.toString(), fundingTargetUnits: initiative.funding_target_units, deadlineGameDay: initiative.funding_deadline_game_day, matchingPolicy: initiative.matching_policy, rulesVersion: 'initiative-funding-v1' };
  });
}

export async function settleDueInitiativesInTransaction(tx: PostgresRepository, gameDay: number): Promise<Record<string, unknown>> {
  const due = await tx.query<{ id: string }>(`SELECT id FROM v5_initiatives WHERE status = 'FUNDING' AND funding_deadline_game_day <= $1 ORDER BY funding_deadline_game_day, id FOR UPDATE SKIP LOCKED`, [gameDay]);
  let settled = 0;
  for (const row of due.rows) {
    const initiative = (await tx.query<{ funding_target_units: string; scope_type: 'EARTH' | 'CORPORATION'; scope_id: string | null }>('SELECT funding_target_units::TEXT, scope_type, scope_id FROM v5_initiatives WHERE id = $1 FOR UPDATE', [row.id])).rows[0];
    if (!initiative) continue;
    const totals = (await tx.query<{ contributed: string; matching: string }>(`SELECT COALESCE(SUM(amount_units),0)::TEXT AS contributed, COALESCE(SUM(matching_units),0)::TEXT AS matching FROM initiative_contributions WHERE initiative_id = $1 AND status = 'ESCROWED'`, [row.id])).rows[0];
    const commitments = (await tx.query<{ id: string; commitment_type: 'TREASURY' | 'MATCHING'; authorized_units: string; committed_units: string; source_type: 'EARTH' | 'CORPORATION'; source_id: string | null }>(`SELECT id, commitment_type, authorized_units::TEXT, committed_units::TEXT, source_type, source_id FROM initiative_funding_commitments WHERE initiative_id = $1 AND status = 'AUTHORIZED' FOR UPDATE`, [row.id])).rows;
    const treasuryCommitment = commitments.find((commitment) => commitment.commitment_type === 'TREASURY');
    const matchingCommitment = commitments.find((commitment) => commitment.commitment_type === 'MATCHING');
    const contributed = BigInt(totals?.contributed ?? '0');
    const matching = BigInt(totals?.matching ?? '0');
    const treasuryAuthorized = BigInt(treasuryCommitment?.authorized_units ?? '0');
    const funded = contributed + matching + treasuryAuthorized >= BigInt(initiative.funding_target_units);
    if (funded) {
      const escrow = (await tx.query<{ id: string }>(`SELECT a.id::TEXT FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.id = 'ECON-CONSTRUCTION-SETTLEMENT' AND o.owner_type = 'SYSTEM' AND a.asset_id = 1 AND a.account_type = 'SYSTEM_ACCOUNT' AND a.status = 'ACTIVE' LIMIT 1`)).rows[0];
      if (!escrow) throw new Error('Initiative escrow account is unavailable');
      const matchingToConsume = matching;
      const treasuryToConsume = [BigInt(initiative.funding_target_units) - contributed - matching, 0n].reduce((a, b) => a > b ? a : b);
      if (matchingToConsume > BigInt(matchingCommitment?.authorized_units ?? '0')) throw new Error('Initiative matching exceeds authorized commitment');
      if (treasuryToConsume > treasuryAuthorized) throw new Error('Initiative treasury funding exceeds authorized commitment');
      for (const funding of [
        { commitment: matchingCommitment, amount: matchingToConsume, kind: 'INITIATIVE_MATCHING_FUNDING' },
        { commitment: treasuryCommitment, amount: treasuryToConsume, kind: 'INITIATIVE_TREASURY_FUNDING' },
      ]) {
        if (!funding.commitment || funding.amount <= 0n) continue;
        const economicId = funding.commitment.source_type === 'EARTH'
          ? 'ECON-EARTH-001'
          : (await tx.query<{ economic_id: string }>(`SELECT economic_id FROM owner_registry WHERE id = $1 AND owner_type = 'CORPORATION'`, [funding.commitment.source_id])).rows[0]?.economic_id;
        const source = economicId ? (await tx.query<{ id: string; balance_units: string }>(`SELECT id::TEXT, balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'TREASURY' AND status = 'ACTIVE' FOR UPDATE`, [economicId])).rows[0] : null;
        if (!source || BigInt(source.balance_units) < funding.amount) throw new Error(`${funding.kind} source is unavailable or underfunded`);
        const posted = await postSettlementTransaction(tx, { correlationId: `initiative-funding:${row.id}:${funding.commitment.commitment_type}`, gameDay, kind: funding.kind, sourceType: funding.commitment.source_type, sourceId: funding.commitment.source_id ?? 'EARTH', rulesVersion: 'v5-initiative-funding-v1', entries: [{ accountId: source.id, assetId: 1, deltaUnits: (-funding.amount).toString() }, { accountId: escrow.id, assetId: 1, deltaUnits: funding.amount.toString() }] });
        await tx.query(`UPDATE initiative_funding_commitments SET committed_units = committed_units + $2, status = 'COMMITTED' WHERE id = $1`, [funding.commitment.id, funding.amount.toString()]);
        if (!posted.created) throw new Error('Initiative funding transaction was already posted before commitment update');
        await createGameEvent(tx, { id: `INITIATIVE-FUNDING-${row.id}-${funding.commitment.commitment_type}`, category: 'INITIATIVE', eventType: funding.kind, gameDay, subjectType: 'INITIATIVE', subjectId: row.id, title: funding.kind === 'INITIATIVE_MATCHING_FUNDING' ? 'Initiative matching committed' : 'Initiative treasury funding committed', details: { initiativeId: row.id, commitmentType: funding.commitment.commitment_type, amountUnits: funding.amount.toString(), transactionId: posted.transactionId }, correlationId: `initiative-funding-event:${row.id}:${funding.commitment.commitment_type}` });
      }
      await tx.query("UPDATE initiative_contributions SET status = 'APPLIED', settled_game_day = $2 WHERE initiative_id = $1 AND status = 'ESCROWED'", [row.id, gameDay]);
      await tx.query("UPDATE initiative_funding_commitments SET status = 'RELEASED' WHERE initiative_id = $1 AND status = 'AUTHORIZED'", [row.id]);
      // Funding completion only unlocks execution. It is not execution progress.
      await tx.query("UPDATE v5_initiatives SET status = 'EXECUTING' WHERE id = $1", [row.id]);
      await tx.query("UPDATE initiative_executions SET status = 'ACTIVE', started_game_day = $2 WHERE initiative_id = $1 AND status = 'PENDING'", [row.id, gameDay]);
    } else {
      const refunds = await tx.query<{ id: string; amount_units: string; escrow_account_id: string; house_id: string }>(`SELECT c.id, c.amount_units::TEXT, c.escrow_account_id::TEXT, c.house_id FROM initiative_contributions c WHERE c.initiative_id = $1 AND c.status = 'ESCROWED' FOR UPDATE`, [row.id]);
      for (const refund of refunds.rows) {
        const wallet = (await tx.query<{ id: string }>(`SELECT a.id::TEXT FROM economic_accounts a JOIN owner_registry o ON o.id = $1 AND o.owner_economic_id = a.owner_economic_id WHERE o.owner_type = 'HOUSE' AND a.asset_id = 1 AND a.account_type = 'WALLET' AND a.status = 'ACTIVE'`, [refund.house_id])).rows[0];
        if (!wallet || !refund.escrow_account_id) throw new Error('Initiative refund account is unavailable');
        const refundPosting = await postSettlementTransaction(tx, { correlationId: `initiative-refund:${refund.id}`, gameDay, kind: 'INITIATIVE_REFUND', sourceType: 'INITIATIVE', sourceId: row.id, rulesVersion: 'v5-initiative-v1', entries: [{ accountId: refund.escrow_account_id, assetId: 1, deltaUnits: (-BigInt(refund.amount_units)).toString() }, { accountId: wallet.id, assetId: 1, deltaUnits: refund.amount_units }] });
        await createGameEvent(tx, { id: `INITIATIVE-REFUND-${refund.id}`, category: 'INITIATIVE', eventType: 'INITIATIVE_CONTRIBUTION_REFUNDED', gameDay, actorHouseId: refund.house_id, subjectType: 'INITIATIVE', subjectId: row.id, title: 'Initiative contribution refunded', details: { initiativeId: row.id, contributionId: refund.id, amountUnits: refund.amount_units, transactionId: refundPosting.transactionId }, correlationId: `initiative-refund-event:${refund.id}` });
      }
      await tx.query("UPDATE initiative_contributions SET status = 'REFUNDED', settled_game_day = $2 WHERE initiative_id = $1 AND status = 'ESCROWED'", [row.id, gameDay]);
      await tx.query("UPDATE initiative_funding_commitments SET status = 'RELEASED' WHERE initiative_id = $1 AND status = 'AUTHORIZED'", [row.id]);
      await tx.query("UPDATE v5_initiatives SET status = 'FAILED' WHERE id = $1", [row.id]);
      await tx.query("UPDATE initiative_executions SET status = 'FAILED' WHERE initiative_id = $1 AND status = 'PENDING'", [row.id]);
      await tx.query("UPDATE initiative_outcomes SET status = 'FAILED' WHERE initiative_id = $1 AND status = 'PENDING'", [row.id]);
    }
    settled += 1;
  }
  return { ok: true, gameDay, settled };
}

/** Advances execution only. Funding is deliberately not used as progress. */
export async function advanceInitiativeExecutionsInTransaction(tx: PostgresRepository, gameDay: number): Promise<Record<string, unknown>> {
  const active = await tx.query<{
    initiative_id: string; progress_model: 'FUNDING_ONLY' | 'TIME' | 'TIME_AND_RESOURCES';
    started_game_day: number | null; required_duration_game_days: string | null;
    required_resource_requirements: Record<string, string>; status: string;
  }>(`SELECT initiative_id, progress_model, started_game_day, required_duration_game_days,
             required_resource_requirements, status
        FROM initiative_executions
       WHERE status IN ('ACTIVE','WAITING_RESOURCES')
       ORDER BY initiative_id
       FOR UPDATE SKIP LOCKED`);
  let completed = 0;
  let waiting = 0;
  for (const execution of active.rows) {
    const requirements = execution.required_resource_requirements ?? {};
    const hasRequirements = Object.keys(requirements).length > 0;
    if (execution.progress_model === 'TIME_AND_RESOURCES' && hasRequirements) {
      await tx.query(`UPDATE initiative_executions SET status = 'WAITING_RESOURCES', blocked_reason = $2 WHERE initiative_id = $1`, [execution.initiative_id, 'REQUIRED_RESOURCES_NOT_AVAILABLE_TO_EXECUTION']);
      waiting += 1;
      continue;
    }
    const progress = execution.progress_model === 'FUNDING_ONLY'
      ? 10000
      : Math.min(10000, Math.floor(((gameDay - Number(execution.started_game_day ?? gameDay) + 1) * 10000) / Number(execution.required_duration_game_days)));
    const done = progress >= 10000;
    await tx.query(`UPDATE initiative_executions
                       SET progress_bps = $2, status = $3, completed_game_day = CASE WHEN $3 = 'COMPLETED' THEN $4 ELSE completed_game_day END,
                           blocked_reason = NULL
                     WHERE initiative_id = $1`, [execution.initiative_id, progress, done ? 'COMPLETED' : 'ACTIVE', gameDay]);
    if (done) {
      await tx.query(`UPDATE v5_initiatives SET status = 'COMPLETED' WHERE id = $1`, [execution.initiative_id]);
      const pendingOutcome = (await tx.query<{ id: string; outcome: unknown }>(`SELECT id, outcome FROM initiative_outcomes WHERE initiative_id = $1 AND status = 'PENDING' FOR UPDATE`, [execution.initiative_id])).rows[0];
      if (!pendingOutcome) throw new Error(`Initiative ${execution.initiative_id} has no pending typed outcome`);
      await applyInitiativeOutcome(tx, { initiativeId: execution.initiative_id, outcomeId: pendingOutcome.id, outcome: validateInitiativeOutcome(pendingOutcome.outcome), gameDay });
      await tx.query(`UPDATE initiative_outcomes SET status = 'APPLIED', applied_game_day = $2 WHERE id = $1 AND status = 'PENDING'`, [pendingOutcome.id, gameDay]);
      await createGameEvent(tx, { id: `INITIATIVE-EXECUTION-COMPLETED-${execution.initiative_id}`, category: 'INITIATIVE', eventType: 'INITIATIVE_EXECUTION_COMPLETED', gameDay, subjectType: 'INITIATIVE', subjectId: execution.initiative_id, title: 'Initiative execution completed', details: { initiativeId: execution.initiative_id, outcomeId: pendingOutcome.id, progressBps: 10000 }, correlationId: `initiative-execution-completed:${execution.initiative_id}` });
      completed += 1;
    }
  }
  return { ok: true, gameDay, completed, waiting };
}
