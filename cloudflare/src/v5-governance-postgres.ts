import type { PostgresRepository } from './repository.ts';
import { createGameEvent } from './game-events-postgres.ts';
import { validateV5GovernanceAction, type V5GovernanceAction } from './v5-governance.ts';

type ProposalAction = V5GovernanceAction & { corporationId?: string };

function currentDay(tx: PostgresRepository): Promise<number> {
  return tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'").then((result) => Number(result.rows[0]?.game_day ?? 1));
}

function bigintPayload(value: unknown, field: string): bigint {
  try { return BigInt(String(value ?? '')); } catch (_error) { throw new Error(`${field} must be an integer`); }
}

function actionFromPayload(actionType: ProposalAction['actionType'], payload: Record<string, unknown>): ProposalAction {
  const action: ProposalAction = {
    actionType,
    effectiveFromGameDay: Number(payload.effectiveFromGameDay),
    corporationId: payload.corporationId == null ? undefined : String(payload.corporationId),
    earthBaseRateUnits: payload.earthBaseRateUnits == null ? undefined : bigintPayload(payload.earthBaseRateUnits, 'EARTH base capacity rate'),
    standardTerritoryCapacityUnits: payload.standardTerritoryCapacityUnits == null ? undefined : bigintPayload(payload.standardTerritoryCapacityUnits, 'Standard Territory capacity'),
    houseBaseRateUnits: payload.houseBaseRateUnits == null ? undefined : bigintPayload(payload.houseBaseRateUnits, 'Corporation House capacity rate'),
    admissionPolicy: payload.admissionPolicy as ProposalAction['admissionPolicy'],
    scheduleId: payload.scheduleId == null ? undefined : String(payload.scheduleId),
    authorityInstitutionId: payload.authorityInstitutionId == null ? undefined : String(payload.authorityInstitutionId),
    scheduleCode: payload.scheduleCode == null ? undefined : String(payload.scheduleCode),
    scheduleBasisType: payload.scheduleBasisType as ProposalAction['scheduleBasisType'],
    brackets: Array.isArray(payload.brackets) ? payload.brackets.map((item) => {
      const row = item as Record<string, unknown>;
      return { ordinal: Number(row.ordinal), lowerBound: bigintPayload(row.lowerBound, 'Bracket lower bound'), upperBound: row.upperBound == null ? null : bigintPayload(row.upperBound, 'Bracket upper bound'), multiplierNumerator: bigintPayload(row.multiplierNumerator, 'Bracket numerator'), multiplierDenominator: bigintPayload(row.multiplierDenominator, 'Bracket denominator') };
    }) : undefined,
  };
  return action;
}

async function canPropose(tx: PostgresRepository, humanId: string, subjectType: 'EARTH' | 'CORPORATION', subjectId: string | null): Promise<{ houseId: string }> {
  const human = (await tx.query<{ house_id: string }>("SELECT house_id FROM humans WHERE id = $1 AND status = 'ACTIVE'", [humanId])).rows[0];
  if (!human) throw new Error('Active Human not found');
  if (subjectType === 'EARTH') return human;
  const member = (await tx.query(`SELECT 1 FROM house_affiliations WHERE house_id = $1 AND corporation_id = $2 AND status = 'ACTIVE'`, [human.house_id, subjectId])).rows[0];
  if (!member) throw new Error('Corporation membership is required to propose');
  return human;
}

async function canVote(tx: PostgresRepository, humanId: string, proposal: { subject_type: 'EARTH' | 'CORPORATION'; subject_id: string | null }): Promise<string> {
  const human = (await tx.query<{ house_id: string }>("SELECT house_id FROM humans WHERE id = $1 AND status = 'ACTIVE'", [humanId])).rows[0];
  if (!human) throw new Error('Active Human not found');
  if (proposal.subject_type === 'CORPORATION' && !(await tx.query(`SELECT 1 FROM house_affiliations WHERE house_id = $1 AND corporation_id = $2 AND status = 'ACTIVE'`, [human.house_id, proposal.subject_id])).rows[0]) throw new Error('Corporation membership is required to vote');
  return human.house_id;
}

export async function listV5GovernanceProposals(repository: PostgresRepository, humanId: string) {
  const result = await repository.query(`
    SELECT p.id, p.subject_type, p.subject_id, p.action_type, p.payload,
           p.status, p.submitted_game_day, p.voting_start_game_day,
           p.voting_end_game_day, p.effective_from_game_day,
           p.support_votes, p.oppose_votes, p.quorum_met,
           GREATEST(1, CEIL((SELECT COUNT(*) FROM houses h WHERE h.status = 'ACTIVE') * 0.25))::INTEGER AS quorum_required,
           (b.proposal_id IS NOT NULL) AS viewer_voted,
           b.choice AS viewer_choice
      FROM v5_governance_proposals p
      LEFT JOIN v5_governance_ballots b
        ON b.proposal_id = p.id
       AND b.house_id = (SELECT house_id FROM humans WHERE id = $1)
     WHERE p.status IN ('VOTING','PASSED')
       AND (p.subject_type = 'EARTH'
        OR (p.subject_type = 'CORPORATION' AND p.subject_id IN (
             SELECT corporation_id FROM house_affiliations
              WHERE house_id = (SELECT house_id FROM humans WHERE id = $1)
                AND status = 'ACTIVE')))
     ORDER BY p.status ASC, p.voting_end_game_day ASC, p.id DESC`, [humanId]);
  return { ok: true, proposals: result.rows, generatedFrom: 'postgres-canonical-facts-v5' };
}

export async function createV5GovernanceProposal(repository: PostgresRepository, input: { humanId: string; subjectType: 'EARTH' | 'CORPORATION'; subjectId: string | null; actionType: ProposalAction['actionType']; payload: Record<string, unknown>; title: string; body?: string; correlationId: string }) {
  return repository.transaction(async (tx) => {
    const prior = (await tx.query('SELECT * FROM v5_governance_proposals WHERE correlation_id = $1', [input.correlationId])).rows[0];
    if (prior) return { ok: true, alreadyProcessed: true, proposal: prior, correlationId: input.correlationId };
    if (input.subjectType === 'EARTH' && input.actionType === 'CORPORATION_HOUSE_RATE' || input.subjectType === 'CORPORATION' && input.actionType === 'EARTH_CAPACITY_POLICY') throw new Error('Policy subject and action scope do not match');
    await canPropose(tx, input.humanId, input.subjectType, input.subjectId);
    const day = await currentDay(tx);
    const action = actionFromPayload(input.actionType, input.payload);
    validateV5GovernanceAction(action, day);
    if (input.actionType === 'CORPORATION_HOUSE_RATE' || input.actionType === 'CORPORATION_ADMISSION_POLICY') {
      if (!input.subjectId || action.corporationId !== input.subjectId) throw new Error('Corporation action must target its proposal Corporation');
    }
    const proposalId = `V5-GOV-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    const effective = action.effectiveFromGameDay;
    await tx.query(`INSERT INTO v5_governance_proposals (id, subject_type, subject_id, action_type, payload, status, submitted_game_day, voting_start_game_day, voting_end_game_day, effective_from_game_day, created_by_human_id, correlation_id)
      VALUES ($1,$2,$3,$4,$5::JSONB,'VOTING',$6,$6 + 1,$6 + 3,$7,$8,$9)`, [proposalId, input.subjectType, input.subjectId, input.actionType, JSON.stringify(input.payload), day, effective, input.humanId, input.correlationId]);
    await createGameEvent(tx, { id: `V5-GOV-CREATED-${proposalId}`, category: 'GOVERNANCE', eventType: 'V5_POLICY_PROPOSAL_CREATED', gameDay: day, actorHumanId: input.humanId, subjectType: input.subjectType, subjectId: input.subjectId ?? 'EARTH', title: input.title.trim(), details: { proposalId, actionType: input.actionType, effectiveFromGameDay: effective, body: input.body?.trim() ?? '' }, correlationId: input.correlationId });
    return { ok: true, proposal: (await tx.query('SELECT * FROM v5_governance_proposals WHERE id = $1', [proposalId])).rows[0], correlationId: input.correlationId };
  });
}

export async function castV5GovernanceVote(repository: PostgresRepository, input: { humanId: string; proposalId: string; choice: 'SUPPORT' | 'OPPOSE' | 'ABSTAIN'; correlationId: string }) {
  return repository.transaction(async (tx) => {
    const proposal = (await tx.query<{ subject_type: 'EARTH' | 'CORPORATION'; subject_id: string | null; voting_end_game_day: number; status: string }>('SELECT subject_type, subject_id, voting_end_game_day, status FROM v5_governance_proposals WHERE id = $1 FOR UPDATE', [input.proposalId])).rows[0];
    if (!proposal || proposal.status !== 'VOTING') throw new Error('V5 governance proposal is not open for voting');
    const day = await currentDay(tx);
    if (day < proposal.voting_end_game_day - 2 || day > proposal.voting_end_game_day) throw new Error('V5 governance voting is not open');
    const houseId = await canVote(tx, input.humanId, proposal);
    await tx.query(`INSERT INTO v5_governance_ballots (proposal_id, house_id, cast_by_human_id, choice, cast_game_day, correlation_id) VALUES ($1,$2,$3,$4,$5,$6)
      ON CONFLICT (proposal_id, house_id) DO UPDATE SET choice = EXCLUDED.choice, cast_by_human_id = EXCLUDED.cast_by_human_id, cast_game_day = EXCLUDED.cast_game_day, correlation_id = EXCLUDED.correlation_id`, [input.proposalId, houseId, input.humanId, input.choice, day, input.correlationId]);
    const totals = (await tx.query<{ support: string; oppose: string }>(`SELECT COUNT(*) FILTER (WHERE choice = 'SUPPORT')::TEXT AS support, COUNT(*) FILTER (WHERE choice = 'OPPOSE')::TEXT AS oppose FROM v5_governance_ballots WHERE proposal_id = $1`, [input.proposalId])).rows[0];
    await tx.query('UPDATE v5_governance_proposals SET support_votes = $1, oppose_votes = $2 WHERE id = $3', [totals?.support ?? '0', totals?.oppose ?? '0', input.proposalId]);
    return { ok: true, proposalId: input.proposalId, houseId, choice: input.choice, correlationId: input.correlationId };
  });
}

export async function resolveV5GovernanceProposal(repository: PostgresRepository, proposalId: string) {
  return repository.transaction(async (tx) => {
    const proposal = (await tx.query<any>('SELECT * FROM v5_governance_proposals WHERE id = $1 FOR UPDATE', [proposalId])).rows[0];
    if (!proposal) throw new Error('V5 governance proposal not found');
    if (proposal.status !== 'VOTING') return { ok: true, alreadyProcessed: true, proposal };
    const day = await currentDay(tx);
    if (day <= Number(proposal.voting_end_game_day)) throw new Error('V5 governance voting period is still open');
    const electorate = proposal.subject_type === 'CORPORATION'
      ? await tx.query<{ count: string }>('SELECT COUNT(*)::TEXT AS count FROM house_affiliations WHERE corporation_id = $1 AND status = \'ACTIVE\'', [proposal.subject_id])
      : await tx.query<{ count: string }>("SELECT COUNT(*)::TEXT AS count FROM houses WHERE status = 'ACTIVE'");
    const voters = Number(proposal.support_votes) + Number(proposal.oppose_votes);
    const eligible = Math.max(1, Number(electorate.rows[0]?.count ?? 0));
    const quorumMet = voters * 4 >= eligible;
    const passed = quorumMet && Number(proposal.support_votes) >= Number(proposal.oppose_votes) && Number(proposal.support_votes) > 0;
    const status = passed ? 'PASSED' : 'REJECTED';
    await tx.query('UPDATE v5_governance_proposals SET status = $1, quorum_met = $2 WHERE id = $3', [status, quorumMet, proposalId]);
    if (passed) await tx.query(`INSERT INTO v5_governance_activation_queue (proposal_id, action_type, payload, effective_from_game_day) VALUES ($1,$2,$3::JSONB,$4) ON CONFLICT (proposal_id) DO NOTHING`, [proposalId, proposal.action_type, JSON.stringify(proposal.payload), proposal.effective_from_game_day]);
    return { ok: true, proposalId, status, quorumMet, supportVotes: Number(proposal.support_votes), opposeVotes: Number(proposal.oppose_votes), effectiveFromGameDay: passed ? Number(proposal.effective_from_game_day) : null };
  });
}

async function retireActive(tx: PostgresRepository, table: string, keyColumn: string, keyValue: string, effective: number): Promise<void> {
  await tx.query(`UPDATE ${table} SET status = 'RETIRED' WHERE ${keyColumn} = $1 AND status = 'ACTIVE'`, [keyValue]);
  await tx.query(`UPDATE ${table} SET effective_to_game_day = $2 WHERE ${keyColumn} = $1 AND status = 'RETIRED' AND effective_to_game_day IS NULL`, [keyValue, effective - 1]);
}

async function applyActivation(tx: PostgresRepository, row: { proposal_id: string; action_type: string; payload: Record<string, unknown>; effective_from_game_day: number }, day: number): Promise<void> {
  const payload = row.payload;
  const effective = Number(row.effective_from_game_day);
  const action = actionFromPayload(row.action_type as ProposalAction['actionType'], payload);
  if (row.action_type === 'CORPORATION_ADMISSION_POLICY') {
    const corporationId = String(action.corporationId);
    await tx.query("UPDATE corporations SET admission_policy = $1 WHERE id = $2", [action.admissionPolicy, corporationId]);
    await tx.query("UPDATE v5_corporation_admission_policy_versions SET status = 'RETIRED', effective_to_game_day = $2 WHERE corporation_id = $1 AND status = 'ACTIVE'", [corporationId, effective - 1]);
    const version = Number((await tx.query<{ version: number }>('SELECT COALESCE(MAX(version),0) + 1 AS version FROM v5_corporation_admission_policy_versions WHERE corporation_id = $1', [corporationId])).rows[0]?.version ?? 1);
    await tx.query(`INSERT INTO v5_corporation_admission_policy_versions (id, corporation_id, version, admission_policy, effective_from_game_day, status, proposal_id) VALUES ($1,$2,$3,$4,$5,'ACTIVE',$6)`, [`V5-ADM-${row.proposal_id}`, corporationId, version, action.admissionPolicy, effective, row.proposal_id]);
  } else if (row.action_type === 'CORPORATION_HOUSE_RATE') {
    const corporationId = String(action.corporationId);
    const prior = (await tx.query<{ house_schedule_id: string }>(`SELECT house_schedule_id FROM corporation_capacity_policy_versions WHERE corporation_id = $1 AND status = 'ACTIVE' ORDER BY version DESC LIMIT 1`, [corporationId])).rows[0];
    if (!prior) throw new Error('Corporation has no active capacity schedule');
    await tx.query("UPDATE corporation_capacity_policy_versions SET status = 'RETIRED', effective_to_game_day = $2 WHERE corporation_id = $1 AND status = 'ACTIVE'", [corporationId, effective - 1]);
    const version = Number((await tx.query<{ version: number }>('SELECT COALESCE(MAX(version),0) + 1 AS version FROM corporation_capacity_policy_versions WHERE corporation_id = $1', [corporationId])).rows[0]?.version ?? 1);
    await tx.query(`INSERT INTO corporation_capacity_policy_versions (id, corporation_id, version, house_base_capacity_rate_units, house_schedule_id, effective_from_game_day, status) VALUES ($1,$2,$3,$4,$5,$6,'ACTIVE')`, [`V5-CORP-RATE-${row.proposal_id}`, corporationId, version, action.houseBaseRateUnits!.toString(), prior.house_schedule_id, effective]);
  } else if (row.action_type === 'EARTH_CAPACITY_POLICY') {
    const prior = (await tx.query<{ earth_corporation_schedule_id: string; earth_house_schedule_id: string }>(`SELECT earth_corporation_schedule_id, earth_house_schedule_id FROM v5_capacity_policy_versions WHERE status = 'ACTIVE' ORDER BY version DESC LIMIT 1`)).rows[0];
    if (!prior) throw new Error('EARTH has no active capacity policy');
    await tx.query("UPDATE v5_capacity_policy_versions SET status = 'RETIRED', effective_to_game_day = $1 WHERE status = 'ACTIVE'", [effective - 1]);
    const version = Number((await tx.query<{ version: number }>('SELECT COALESCE(MAX(version),0) + 1 AS version FROM v5_capacity_policy_versions')).rows[0]?.version ?? 1);
    await tx.query(`INSERT INTO v5_capacity_policy_versions (id, version, standard_territory_capacity_units, earth_base_capacity_rate_units, earth_corporation_schedule_id, earth_house_schedule_id, effective_from_game_day, status) VALUES ($1,$2,$3,$4,$5,$6,$7,'ACTIVE')`, [`V5-EARTH-POLICY-${row.proposal_id}`, version, action.standardTerritoryCapacityUnits!.toString(), action.earthBaseRateUnits!.toString(), prior.earth_corporation_schedule_id, prior.earth_house_schedule_id, effective]);
  } else {
    const scheduleId = `V5-GOV-SCHEDULE-${row.proposal_id}`;
    await retireActive(tx, 'progressive_policy_schedules', 'code', String(action.scheduleCode), effective);
    const version = Number((await tx.query<{ version: number }>('SELECT COALESCE(MAX(version),0) + 1 AS version FROM progressive_policy_schedules WHERE code = $1', [action.scheduleCode])).rows[0]?.version ?? 1);
    await tx.query(`INSERT INTO progressive_policy_schedules (id, code, basis_type, authority_institution_id, version, status, effective_from_game_day, created_by) VALUES ($1,$2,$3,$4,$5,'DRAFT',$6,$7)`, [scheduleId, action.scheduleCode, action.scheduleBasisType, action.authorityInstitutionId, version, effective, payload.createdByHumanId ?? null]);
    for (const bracket of action.brackets ?? []) await tx.query(`INSERT INTO progressive_policy_brackets (schedule_id, ordinal, lower_bound_units, upper_bound_units, marginal_multiplier_numerator, marginal_multiplier_denominator) VALUES ($1,$2,$3,$4,$5,$6)`, [scheduleId, bracket.ordinal, bracket.lowerBound.toString(), bracket.upperBound?.toString() ?? null, bracket.multiplierNumerator.toString(), bracket.multiplierDenominator.toString()]);
    await tx.query("UPDATE progressive_policy_schedules SET status = 'ACTIVE' WHERE id = $1", [scheduleId]);
  }
  await tx.query("UPDATE v5_governance_activation_queue SET status = 'APPLIED', applied_game_day = $2 WHERE proposal_id = $1", [row.proposal_id, day]);
  await tx.query("UPDATE v5_governance_proposals SET status = 'EXECUTED' WHERE id = $1", [row.proposal_id]);
}

export async function activateDueV5GovernancePoliciesInTransaction(tx: PostgresRepository, day: number) {
  const rows = (await tx.query<{ proposal_id: string; action_type: string; payload: Record<string, unknown>; effective_from_game_day: number }>(`SELECT proposal_id, action_type, payload, effective_from_game_day FROM v5_governance_activation_queue WHERE status = 'PENDING' AND effective_from_game_day <= $1 ORDER BY effective_from_game_day, proposal_id FOR UPDATE`, [day])).rows;
  let applied = 0; let failed = 0;
  for (const row of rows) {
    try { await applyActivation(tx, row, day); applied += 1; } catch (error) { failed += 1; await tx.query("UPDATE v5_governance_activation_queue SET status = 'FAILED', error_message = $2 WHERE proposal_id = $1", [row.proposal_id, error instanceof Error ? error.message : 'Activation failed']); }
  }
  return { ok: true, day, applied, failed };
}
