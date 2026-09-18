import type { PostgresRepository } from './repository.ts';
import { createGameEvent } from './game-events-postgres.ts';
import type { VotingMethod } from './governance-voting.ts';
import { evaluateOneHouseVote } from './governance-decision.ts';
import { resolveEffectiveConstitution } from './constitutional-kernel-postgres.ts';
import { proposalActionHandler } from './proposal-actions.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';

const VOTING_METHODS = new Set<VotingMethod>(['ONE_HOUSE_ONE_VOTE', 'DELEGATED', 'SHARE_WEIGHTED', 'QUADRATIC_VOICE']);

function object(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {};
}

async function currentDay(tx: PostgresRepository): Promise<number> {
  return (await readAuthoritativeGameTime(tx)).gameDay;
}

async function canGovern(tx: PostgresRepository, humanId: string, subjectType: 'EARTH' | 'ORGANIZATION', subjectId: string | null): Promise<string> {
  const human = (await tx.query<{ house_id: string }>("SELECT house_id FROM humans WHERE id = $1 AND status = 'ACTIVE'", [humanId])).rows[0];
  if (!human) throw new Error('Active Human not found');
  if (subjectType === 'EARTH') return human.house_id;
  // organization_capabilities remains a compatibility mirror; the charter is authoritative.
  const allowed = await tx.query(`SELECT 1 FROM organization_memberships m JOIN organization_charter_versions v ON v.organization_id = m.organization_id AND v.effective_from_game_day <= (SELECT game_day FROM earth_get_current_game_time()) AND (v.effective_to_game_day IS NULL OR v.effective_to_game_day >= (SELECT game_day FROM earth_get_current_game_time())) WHERE m.organization_id = $1 AND m.house_id = $2 AND m.status = 'ACTIVE' AND (v.charter->'capabilities') ? 'GOVERNANCE'`, [subjectId, human.house_id]);
  if (!allowed.rows[0]) throw new Error('Organization governance capability denied');
  return human.house_id;
}

async function canVote(tx: PostgresRepository, humanId: string, proposalId: string): Promise<string> {
  const human = (await tx.query<{ house_id: string }>("SELECT house_id FROM humans WHERE id = $1 AND status = 'ACTIVE'", [humanId])).rows[0];
  if (!human) throw new Error('Active Human not found');
  const eligible = await tx.query('SELECT 1 FROM governance_electorate_snapshots_v4 WHERE proposal_id = $1 AND house_id = $2', [proposalId, human.house_id]);
  if (!eligible.rows[0]) throw new Error('House was not in the frozen V4 electorate');
  return human.house_id;
}

export async function getOrganizationVotingSettings(repository: PostgresRepository, organizationId: string): Promise<Record<string, unknown>> {
  const result = await repository.query(`SELECT s.organization_id, COALESCE(s.voting_method, v.charter->>'votingMethod') AS voting_method, s.voice_cycle_days, s.voice_per_cycle FROM organization_charter_versions v LEFT JOIN organization_governance_settings s ON s.organization_id = v.organization_id WHERE v.organization_id = $1 AND v.effective_from_game_day <= (SELECT game_day FROM earth_get_current_game_time()) AND (v.effective_to_game_day IS NULL OR v.effective_to_game_day >= (SELECT game_day FROM earth_get_current_game_time())) ORDER BY v.version DESC LIMIT 1`, [organizationId]);
  if (!result.rows[0]) throw new Error('Organization not found');
  return { organizationId, settings: result.rows[0], generatedFrom: 'postgres-canonical-facts' };
}

export async function setOrganizationVotingSettings(repository: PostgresRepository, input: { organizationId: string; humanId: string; votingMethod: VotingMethod; voiceCycleDays?: number; voicePerCycle?: number; correlationId: string }): Promise<Record<string, unknown>> {
  // This service remains exported for historical replay/tooling compatibility,
  // but it must never be a gameplay mutation path. Corporation governance
  // settings are constitutional V5 rules and can only change through a typed
  // amendment proposal and activation.
  throw new Error('Direct voting-setting mutation is retired; submit a V5 Constitution amendment proposal.');
  /* istanbul ignore next -- retained below only for historical migration callers. */
  if (!VOTING_METHODS.has(input.votingMethod)) throw new Error('Unsupported voting method');
  return repository.transaction(async (tx) => {
    const human = (await tx.query<{ house_id: string }>("SELECT house_id FROM humans WHERE id = $1 AND status = 'ACTIVE'", [input.humanId])).rows[0];
    if (!human) throw new Error('Active Human not found');
    await canGovern(tx, input.humanId, 'ORGANIZATION', input.organizationId);
    const day = await currentDay(tx);
    const cycleDays = input.voiceCycleDays ?? 7;
    const voicePerCycle = input.voicePerCycle ?? 100;
    if (cycleDays < 1 || cycleDays > 30 || voicePerCycle < 0 || voicePerCycle > 100000) throw new Error('Invalid Voice cycle settings');
    await tx.query(`INSERT INTO organization_governance_settings (organization_id, voting_method, voice_cycle_days, voice_per_cycle, updated_game_day, updated_by_human_id) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (organization_id) DO UPDATE SET voting_method = EXCLUDED.voting_method, voice_cycle_days = EXCLUDED.voice_cycle_days, voice_per_cycle = EXCLUDED.voice_per_cycle, updated_game_day = EXCLUDED.updated_game_day, updated_by_human_id = EXCLUDED.updated_by_human_id`, [input.organizationId, input.votingMethod, cycleDays, voicePerCycle, day, input.humanId]);
    await createGameEvent(tx, { id: `GOV4-METHOD-${input.correlationId}`, category: 'GOVERNANCE', eventType: 'ORGANIZATION_VOTING_METHOD_CHANGED', gameDay: day, actorHumanId: input.humanId, subjectType: 'ORGANIZATION', subjectId: input.organizationId, title: 'Organization voting method changed', details: { votingMethod: input.votingMethod, cycleDays, voicePerCycle }, correlationId: input.correlationId });
    return { ok: true, organizationId: input.organizationId, votingMethod: input.votingMethod, voiceCycleDays: cycleDays, voicePerCycle, effectiveFromGameDay: day, correlationId: input.correlationId };
  });
}

function validateAction(actionType: string, actionSnapshot: Record<string, unknown>): void {
  try {
    proposalActionHandler(actionType).validateCreation({ ...actionSnapshot, actionType });
  } catch (error) {
    if (actionType === 'TAX_RULE' || actionType === 'CHARTER_CHANGE') {
      throw new Error('Legacy constitutional governance action is retired; use a V5 Constitution amendment');
    }
    if (error instanceof Error && error.message.startsWith('Unregistered proposal action handler')) throw new Error('Unregistered governance action');
    throw error;
  }
}

export async function createGovernanceProposalV4(repository: PostgresRepository, input: { humanId: string; subjectType: 'EARTH' | 'ORGANIZATION'; subjectId: string | null; title: string; body?: string; actionType: string; actionSnapshot: Record<string, unknown>; ruleSnapshot?: Record<string, unknown>; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query('SELECT * FROM governance_proposals_v4 WHERE correlation_id = $1', [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, proposal: prior.rows[0], correlationId: input.correlationId };
    if (input.subjectType === 'ORGANIZATION' && !input.subjectId) throw new Error('Organization subject is required');
    await canGovern(tx, input.humanId, input.subjectType, input.subjectId);
    validateAction(input.actionType, input.actionSnapshot);
    const submitted = await currentDay(tx);
    const votingStart = submitted + 1;
    const electorate = input.subjectType === 'ORGANIZATION'
      ? await tx.query<{ count: string }>(`SELECT COUNT(*)::TEXT AS count FROM (
          SELECT house_id FROM organization_memberships
           WHERE organization_id = $1 AND status = 'ACTIVE'
             AND joined_game_day <= $2 AND (left_game_day IS NULL OR left_game_day >= $2)
          UNION
          SELECT house_id FROM house_affiliations
           WHERE corporation_id = $1 AND status = 'ACTIVE'
             AND joined_game_day <= $2 AND (left_game_day IS NULL OR left_game_day >= $2)
        ) AS frozen_electorate`, [input.subjectId, votingStart])
      : await tx.query<{ count: string }>("SELECT COUNT(*)::TEXT AS count FROM houses WHERE status = 'ACTIVE'");
    const constitutional = await resolveEffectiveConstitution(tx, {
      gameDay: submitted,
      corporationId: input.subjectType === 'ORGANIZATION' ? input.subjectId ?? undefined : undefined,
    });
    const rulePrefix = input.subjectType === 'EARTH' ? 'EARTH.GOVERNANCE' : 'CORPORATION.GOVERNANCE';
    const constitutionalValue = (suffix: string, fallback: number): number => {
      const value = constitutional.rules[`${rulePrefix}.${suffix}`];
      const parsed = Number(value ?? fallback);
      return Number.isSafeInteger(parsed) ? parsed : fallback;
    };
    const rule = {
      quorumBps: constitutionalValue('POLICY_QUORUM_BPS', 5000),
      approvalBps: constitutionalValue('POLICY_APPROVAL_BPS', 5000),
      votingPeriodDays: constitutionalValue('VOTING_PERIOD_DAYS', 2),
      implementationDelayDays: constitutionalValue('IMPLEMENTATION_DELAY_DAYS', 1),
      electorateSnapshotGameDay: votingStart,
      electorateSize: Number(electorate.rows[0]?.count ?? 0),
    };
    const proposalId = `GOV4-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    await tx.query(`INSERT INTO governance_proposals_v4 (id, subject_type, subject_id, title, body, action_type, action_snapshot, rule_snapshot, submitted_game_day, voting_start_game_day, voting_end_game_day, execution_game_day, correlation_id, created_by_human_id) VALUES ($1,$2,$3,$4,$5,$6,$7::JSONB,$8::JSONB,$9,$9,$10,$11,$12,$13)`, [proposalId, input.subjectType, input.subjectId, input.title.trim(), input.body?.trim() ?? '', input.actionType, JSON.stringify(input.actionSnapshot), JSON.stringify(rule), submitted, submitted + 1, submitted + 1 + Number(rule.votingPeriodDays) + Number(rule.implementationDelayDays), input.correlationId, input.humanId]);
    if (input.subjectType === 'ORGANIZATION') {
      await tx.query(`INSERT INTO governance_electorate_snapshots_v4 (proposal_id, house_id, snapshot_game_day)
        SELECT $1, house_id, $2 FROM (
          SELECT house_id FROM organization_memberships
           WHERE organization_id = $3 AND status = 'ACTIVE'
             AND joined_game_day <= $2 AND (left_game_day IS NULL OR left_game_day >= $2)
          UNION
          SELECT house_id FROM house_affiliations
           WHERE corporation_id = $3 AND status = 'ACTIVE'
             AND joined_game_day <= $2 AND (left_game_day IS NULL OR left_game_day >= $2)
        ) AS eligible_houses
        ON CONFLICT (proposal_id, house_id) DO NOTHING`, [proposalId, submitted + 1, input.subjectId]);
    } else {
      await tx.query(`INSERT INTO governance_electorate_snapshots_v4 (proposal_id, house_id, snapshot_game_day)
        SELECT $1, id, $2 FROM houses WHERE status = 'ACTIVE'
        ON CONFLICT (proposal_id, house_id) DO NOTHING`, [proposalId, submitted + 1]);
    }
    await createGameEvent(tx, { id: `GOV4-CREATED-${proposalId}`, category: 'GOVERNANCE', eventType: 'GOVERNANCE_PROPOSAL_CREATED', gameDay: submitted, actorHumanId: input.humanId, subjectType: input.subjectType, subjectId: input.subjectId ?? 'EARTH', title: input.title.trim(), details: { proposalId, actionType }, correlationId: input.correlationId });
    return { ok: true, proposal: (await tx.query('SELECT * FROM governance_proposals_v4 WHERE id = $1', [proposalId])).rows[0], correlationId: input.correlationId };
  });
}

export async function castGovernanceVoteV4(repository: PostgresRepository, input: { proposalId: string; humanId: string; choice: 'SUPPORT' | 'OPPOSE' | 'ABSTAIN'; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const proposal = (await tx.query<{ subject_type: 'EARTH' | 'ORGANIZATION'; subject_id: string | null; voting_end_game_day: number; status: string; rule_snapshot: Record<string, unknown> }>('SELECT subject_type, subject_id, voting_end_game_day, status, rule_snapshot FROM governance_proposals_v4 WHERE id = $1 FOR UPDATE', [input.proposalId])).rows[0];
    if (!proposal || proposal.status !== 'VOTING') throw new Error('Governance proposal is not open for voting');
    const day = await currentDay(tx);
    if (day > proposal.voting_end_game_day) throw new Error('Governance voting deadline has passed');
    const houseId = await canVote(tx, input.humanId, input.proposalId);
    const ballot = await tx.query(`INSERT INTO governance_ballots_v4 (proposal_id, house_id, cast_by_human_id, choice, cast_game_day, correlation_id) VALUES ($1,$2,$3,$4,$5,$6)
      ON CONFLICT (proposal_id, house_id) DO UPDATE SET choice = EXCLUDED.choice, cast_by_human_id = EXCLUDED.cast_by_human_id, cast_game_day = EXCLUDED.cast_game_day, correlation_id = EXCLUDED.correlation_id`, [input.proposalId, houseId, input.humanId, input.choice, day, input.correlationId]);
    if (ballot.rowCount !== 1) throw new Error('Ballot could not be recorded');
    const totals = await tx.query<{ support: string; oppose: string }>(`SELECT COUNT(*) FILTER (WHERE choice = 'SUPPORT')::TEXT AS support, COUNT(*) FILTER (WHERE choice = 'OPPOSE')::TEXT AS oppose FROM governance_ballots_v4 WHERE proposal_id = $1`, [input.proposalId]);
    await tx.query('UPDATE governance_proposals_v4 SET support_votes = $1, oppose_votes = $2 WHERE id = $3', [totals.rows[0]?.support ?? '0', totals.rows[0]?.oppose ?? '0', input.proposalId]);
    return { ok: true, proposalId: input.proposalId, houseId, choice: input.choice, correlationId: input.correlationId };
  });
}

export async function resolveGovernanceProposalV4(repository: PostgresRepository, proposalId: string): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const proposal = (await tx.query<any>('SELECT * FROM governance_proposals_v4 WHERE id = $1 FOR UPDATE', [proposalId])).rows[0];
    if (!proposal) throw new Error('Governance proposal not found');
    if (proposal.status !== 'VOTING') return { ok: true, alreadyProcessed: true, proposal };
    const day = await currentDay(tx);
    if (day <= Number(proposal.voting_end_game_day)) throw new Error('Voting period is still open');
    const ballots = await tx.query<{ abstain: string }>(`SELECT COUNT(*) FILTER (WHERE choice = 'ABSTAIN')::TEXT AS abstain FROM governance_ballots_v4 WHERE proposal_id = $1`, [proposalId]);
    const ruleSnapshot = object(proposal.rule_snapshot);
    const decision = evaluateOneHouseVote({ support: Number(proposal.support_votes), oppose: Number(proposal.oppose_votes), abstain: Number(ballots.rows[0]?.abstain ?? 0), electorateSize: Number(ruleSnapshot.electorateSize ?? 0), quorumBps: Number(ruleSnapshot.quorumBps ?? 5000), approvalBps: Number(ruleSnapshot.approvalBps ?? 5000) });
    const { quorumMet, passed } = decision;
    const status = passed ? 'PASSED' : 'REJECTED';
    await tx.query('UPDATE governance_proposals_v4 SET status = $1 WHERE id = $2', [status, proposalId]);
    if (passed && proposal.action_type === 'WORLD_CONDITION') {
      const handler = proposalActionHandler(proposal.action_type);
      const execution = handler.execute
        ? await handler.execute({ repository: tx, proposal: proposal as Record<string, unknown>, action: object(proposal.action_snapshot), gameDay: day })
        : (() => { throw new Error('Governance action handler has no executor'); })();
      await tx.query('UPDATE governance_proposals_v4 SET status = \'EXECUTED\' WHERE id = $1', [proposalId]);
      return { ok: true, proposalId, status: 'EXECUTED', quorumMet, executionGameDay: proposal.execution_game_day, execution };
    }
    return { ok: true, proposalId, status, quorumMet, executionGameDay: passed ? proposal.execution_game_day : null };
  });
}
