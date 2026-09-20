import type { PostgresRepository } from './repository.ts';
import type { V5GovernanceAction } from './v5-governance.ts';
import { createGameEvent } from './game-events-postgres.ts';
import { validateInitiativeOutcome } from './initiative-outcomes.ts';

type InitiativeSubject = 'EARTH' | 'CORPORATION';

export async function materializeV5Initiative(
  tx: PostgresRepository,
  input: {
    proposalId: string;
    subjectType: InitiativeSubject;
    subjectId: string | null;
    action: V5GovernanceAction;
    effectiveGameDay: number;
    createdGameDay: number;
  },
): Promise<{ initiativeId: string; proposalId: string; status: 'FUNDING' }> {
  if (input.subjectType === 'CORPORATION' && !input.subjectId) throw new Error('Corporation initiative requires a Corporation subject');
  const initiativeId = `INIT-${input.proposalId}`;
  const existing = (await tx.query<{ id: string }>('SELECT id FROM v5_initiatives WHERE governance_proposal_id = $1', [input.proposalId])).rows[0];
  if (existing) return { initiativeId: existing.id, proposalId: input.proposalId, status: 'FUNDING' };

  const target = input.action.fundingTargetUnits;
  if (target == null || target <= 0n) throw new Error('Initiative funding target is missing');
  const treasury = input.action.treasuryAuthorizedUnits ?? 0n;
  const matchingCap = input.action.matchingCapUnits ?? 0n;
  const progressModel = input.action.progressModel ?? (input.action.initiativeType === 'PROGRAM' ? 'TIME' : 'FUNDING_ONLY');
  const executionDuration = input.action.executionDurationGameDays ?? null;
  const resourceRequirements = input.action.executionResourceRequirements ?? {};
  const scopeId = input.subjectType === 'CORPORATION' ? input.subjectId : null;
  await tx.query(
    `INSERT INTO v5_initiatives
      (id, scope_type, scope_id, initiative_type, name, description, program_type,
       funding_target_units, treasury_authorized_units, matching_policy, matching_cap_units,
       funding_deadline_game_day, funding_model, execution_model, outcome,
       physical_target, funding_policy_id, governance_proposal_id, status, effective_game_day, created_game_day)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15::JSONB,$16::JSONB,$17,$18,'FUNDING',$19,$20)
     ON CONFLICT (governance_proposal_id) DO NOTHING`,
    [
      initiativeId,
      input.subjectType,
      scopeId,
      input.action.initiativeType,
      input.action.name!.trim(),
      input.action.initiativeDescription!.trim(),
      input.action.programType ?? null,
      target.toString(),
      treasury.toString(),
      input.action.matchingPolicy,
      matchingCap.toString(),
      input.action.fundingDeadlineGameDay,
      input.action.fundingModel,
      input.action.executionModel,
      JSON.stringify(input.action.outcome),
      input.action.physicalTarget == null ? null : JSON.stringify(input.action.physicalTarget),
      input.action.matchingPolicy === 'LINEAR_MATCH' ? 'INITIATIVE-POLICY-LINEAR-MATCH-V1' : input.action.matchingPolicy === 'BREADTH_MATCH' ? 'INITIATIVE-POLICY-BREADTH-MATCH-V1' : 'INITIATIVE-POLICY-NONE-V1',
      input.proposalId,
      input.effectiveGameDay,
      input.createdGameDay,
    ],
  );
  const commitmentId = `INIT-COMMITMENT-${initiativeId}`;
  await tx.query(
    `INSERT INTO initiative_funding_commitments
      (id, initiative_id, source_type, source_id, authorized_units, committed_units,
       commitment_type, status, governance_proposal_id, created_game_day, correlation_id)
     VALUES ($1,$2,$3,$4,$5,0,'TREASURY','AUTHORIZED',$6,$7,$8)
     ON CONFLICT (initiative_id, source_type, source_id, commitment_type) DO NOTHING`,
    [commitmentId, initiativeId, input.subjectType, scopeId, treasury.toString(), input.proposalId, input.createdGameDay, `initiative-commitment:treasury:${input.proposalId}`],
  );
  await tx.query(
    `INSERT INTO initiative_funding_commitments
      (id, initiative_id, source_type, source_id, authorized_units, committed_units,
       commitment_type, status, governance_proposal_id, created_game_day, correlation_id)
     VALUES ($1,$2,$3,$4,$5,0,'MATCHING','AUTHORIZED',$6,$7,$8)
     ON CONFLICT (initiative_id, source_type, source_id, commitment_type) DO NOTHING`,
    [`${commitmentId}-MATCHING`, initiativeId, input.subjectType, scopeId, matchingCap.toString(), input.proposalId, input.createdGameDay, `initiative-commitment:matching:${input.proposalId}`],
  );
  await tx.query(
    `INSERT INTO initiative_executions
      (id, initiative_id, execution_model, status, required_duration_game_days,
       required_resource_requirements, progress_model, correlation_id)
     VALUES ($1,$2,$3,'PENDING',$4,$5::JSONB,$6,$7)
     ON CONFLICT (initiative_id) DO NOTHING`,
    [`INIT-EXECUTION-${initiativeId}`, initiativeId, input.action.executionModel, executionDuration, JSON.stringify(resourceRequirements), progressModel, `initiative-execution:${input.proposalId}`],
  );
  const outcome = validateInitiativeOutcome(input.action.outcome);
  await tx.query(
    `INSERT INTO initiative_outcomes (id, initiative_id, outcome_type, outcome, effective_game_day, correlation_id)
     VALUES ($1,$2,$3,$4::JSONB,$5,$6)
     ON CONFLICT (correlation_id) DO NOTHING`,
    [`INIT-OUTCOME-${initiativeId}`, initiativeId, String(outcome.type ?? 'UNSPECIFIED'), JSON.stringify(outcome), input.effectiveGameDay, `initiative-outcome:${input.proposalId}`],
  );
  await createGameEvent(tx, {
    id: `INITIATIVE-ACTIVATED-${input.proposalId}`,
    category: 'GOVERNANCE',
    eventType: 'V5_INITIATIVE_ACTIVATED',
    gameDay: input.createdGameDay,
    subjectType: input.subjectType,
    subjectId: scopeId ?? 'EARTH',
    title: input.action.name!.trim(),
    details: {
      initiativeId,
      proposalId: input.proposalId,
      initiativeType: input.action.initiativeType,
      effectiveGameDay: input.effectiveGameDay,
    },
    correlationId: `initiative-activation:${input.proposalId}`,
  });
  return { initiativeId, proposalId: input.proposalId, status: 'FUNDING' };
}
