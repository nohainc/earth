import type { PostgresRepository } from './repository.ts';
import { createGameEvent } from './game-events-postgres.ts';
import { validateV5GovernanceAction, type V5GovernanceAction } from './v5-governance.ts';
import { assertConstitutionalAmendableRule, getConstitutionalRuleDefinition } from './v5-constitution.ts';
import { resolveEffectiveConstitution } from './constitutional-kernel-postgres.ts';
import { evaluateOneHouseVote } from './governance-decision.ts';
import { validateProposalActionSnapshot } from './proposal-actions.ts';
import { toJsonSafe } from './json-safe.ts';

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
    changes: Array.isArray(payload.changes) ? payload.changes.map((item) => {
      const row = item as Record<string, unknown>;
      return { ruleCode: String(row.ruleCode ?? ''), value: row.value, clearOverride: row.clearOverride === true, baseVersionId: row.baseVersionId == null ? undefined : String(row.baseVersionId) };
    }) : undefined,
  };
  return action;
}

async function assertExistingProgressiveSchedule(
  tx: PostgresRepository,
  scheduleId: string,
): Promise<void> {
  const schedule = (await tx.query<{ id: string }>(
    `SELECT id
       FROM progressive_policy_schedules
      WHERE id = $1 AND status = 'ACTIVE'`,
    [scheduleId],
  )).rows[0];
  if (!schedule) {
    throw new Error(`Progressive schedule is not an active canonical policy: ${scheduleId}`);
  }
}

async function governancePolicy(tx: PostgresRepository, subjectType: 'EARTH' | 'CORPORATION', subjectId: string | null, gameDay: number) {
  const resolved = await resolveEffectiveConstitution(tx, {
    gameDay,
    corporationId: subjectType === 'CORPORATION' ? subjectId ?? undefined : undefined,
  });
  const value = (code: string): number => {
    const raw = resolved.rules[code];
    if (raw === undefined) throw new Error(`Constitution governance rule is unavailable: ${code}`);
    const parsed = Number(raw);
    if (!Number.isSafeInteger(parsed) || parsed < 0) throw new Error(`Invalid Constitution governance rule: ${code}`);
    return parsed;
  };
  return {
    quorumBps: value('CORPORATION.GOVERNANCE.POLICY_QUORUM_BPS'),
    approvalBps: value('CORPORATION.GOVERNANCE.POLICY_APPROVAL_BPS'),
    votingPeriodDays: value('CORPORATION.GOVERNANCE.VOTING_PERIOD_DAYS'),
    implementationDelayDays: value('CORPORATION.GOVERNANCE.IMPLEMENTATION_DELAY_DAYS'),
  };
}

async function canPropose(tx: PostgresRepository, humanId: string, subjectType: 'EARTH' | 'CORPORATION', subjectId: string | null): Promise<{ houseId: string }> {
  const human = (await tx.query<{ house_id: string }>("SELECT house_id FROM humans WHERE id = $1 AND status = 'ACTIVE'", [humanId])).rows[0];
  if (!human) throw new Error('Active Human not found');
  if (subjectType === 'EARTH') return human;
  const member = (await tx.query(`SELECT 1 FROM house_affiliations WHERE house_id = $1 AND corporation_id = $2 AND status = 'ACTIVE'`, [human.house_id, subjectId])).rows[0];
  if (!member) throw new Error('Corporation membership is required to propose');
  return human;
}

async function canVote(tx: PostgresRepository, humanId: string, proposal: { id: string; electorate_snapshot_game_day: number }): Promise<string> {
  const human = (await tx.query<{ house_id: string }>("SELECT house_id FROM humans WHERE id = $1 AND status = 'ACTIVE'", [humanId])).rows[0];
  if (!human) throw new Error('Active Human not found');
  const eligible = (await tx.query(
    'SELECT 1 FROM v5_governance_electorate_snapshots_v5 WHERE proposal_id = $1 AND house_id = $2',
    [proposal.id, human.house_id],
  )).rows[0];
  if (!eligible) throw new Error('House was not in the frozen V5 electorate');
  return human.house_id;
}

export async function listV5GovernanceProposals(repository: PostgresRepository, humanId: string) {
  const result = await repository.query(`
    SELECT p.id, p.subject_type, p.subject_id, p.action_type, p.payload,
           p.status, p.submitted_game_day, p.voting_start_game_day,
           p.voting_end_game_day, p.effective_from_game_day,
           p.support_votes, p.oppose_votes, p.abstain_votes, p.quorum_met,
           p.quorum_bps, p.approval_bps, p.electorate_snapshot_game_day,
           p.electorate_size, p.governance_rule_snapshot, p.base_version_snapshot,
           GREATEST(1, CEIL(p.electorate_size * p.quorum_bps / 10000.0))::INTEGER AS quorum_required,
           (b.proposal_id IS NOT NULL) AS viewer_voted,
           b.choice AS viewer_choice
      FROM v5_governance_proposals p
      LEFT JOIN v5_governance_ballots b
        ON b.proposal_id = p.id
       AND b.house_id = (SELECT house_id FROM humans WHERE id = $1)
     WHERE p.status IN ('VOTING','PASSED','SCHEDULED')
       AND (p.subject_type = 'EARTH'
        OR (p.subject_type = 'CORPORATION' AND p.subject_id IN (
             SELECT corporation_id FROM house_affiliations
              WHERE house_id = (SELECT house_id FROM humans WHERE id = $1)
                AND status = 'ACTIVE')))
     ORDER BY p.status ASC, p.voting_end_game_day ASC, p.id DESC`, [humanId]);
  return { ok: true, proposals: toJsonSafe(result.rows), generatedFrom: 'postgres-canonical-facts-v5' };
}

export async function createV5GovernanceProposal(repository: PostgresRepository, input: { humanId: string; subjectType: 'EARTH' | 'CORPORATION'; subjectId: string | null; actionType: ProposalAction['actionType']; payload: Record<string, unknown>; title: string; body?: string; correlationId: string }) {
  return repository.transaction(async (tx) => {
    const prior = (await tx.query('SELECT * FROM v5_governance_proposals WHERE correlation_id = $1', [input.correlationId])).rows[0];
    if (prior) return { ok: true, alreadyProcessed: true, proposal: toJsonSafe(prior), correlationId: input.correlationId };
    // Specialized V5 actions were the bootstrap bridge for capacity and
    // admission. New gameplay proposals must use one typed Constitution
    // change-set lifecycle; the legacy activation branches below remain only
    // for replaying already-persisted migration records.
    if (input.actionType !== 'CONSTITUTION_AMENDMENT') {
      throw new Error('Legacy V5 policy actions are retired; submit a Constitution amendment proposal.');
    }
    if (input.subjectType === 'EARTH' && ['CORPORATION_HOUSE_RATE', 'CORPORATION_ADMISSION_POLICY'].includes(input.actionType) || input.subjectType === 'CORPORATION' && input.actionType === 'EARTH_CAPACITY_POLICY') throw new Error('Policy subject and action scope do not match');
    await canPropose(tx, input.humanId, input.subjectType, input.subjectId);
    const day = await currentDay(tx);
    const proposalInputPayload = input.actionType === 'CONSTITUTION_AMENDMENT' && Number(input.payload.effectiveFromGameDay ?? 0) <= day
      ? { ...input.payload, effectiveFromGameDay: day + 1 }
      : input.payload;
    const action = actionFromPayload(input.actionType, proposalInputPayload);
    validateV5GovernanceAction(action, day);
    if (input.actionType === 'CONSTITUTION_AMENDMENT') {
      validateProposalActionSnapshot(action as unknown as Record<string, unknown>);
    }
    if (input.actionType === 'CORPORATION_HOUSE_RATE' || input.actionType === 'CORPORATION_ADMISSION_POLICY') {
      if (!input.subjectId || action.corporationId !== input.subjectId) throw new Error('Corporation action must target its proposal Corporation');
    }
    if (input.actionType === 'CONSTITUTION_AMENDMENT') {
      const changes = action.changes ?? [];
      const groups = new Set<string>();
      for (const change of changes) {
        const rule = assertConstitutionalAmendableRule(change.ruleCode);
        groups.add(rule.policyGroup);
        if (input.subjectType === 'EARTH' && rule.authorityModel === 'CORPORATION_LOCAL') throw new Error('Corporation-local rule cannot be amended at Earth scope');
        if (input.subjectType === 'CORPORATION' && rule.authorityModel === 'EARTH_LOCKED') throw new Error('Earth-locked rule cannot be amended at Corporation scope');
        if (change.clearOverride && input.subjectType !== 'CORPORATION') throw new Error('Only a Corporation can clear its Earth-default override');
        if (change.clearOverride && rule.authorityModel !== 'EARTH_DEFAULT_CORPORATION_OVERRIDE') throw new Error('Only Earth-default Corporation overrides can be cleared');
        if (rule.valueType === 'PROGRESSIVE_SCHEDULE_REF' && typeof change.value === 'string') {
          await assertExistingProgressiveSchedule(tx, change.value);
        }
      }
      if (groups.size !== 1) throw new Error('A Constitution amendment must contain one policy group');
    }
    const scope = input.subjectType === 'CORPORATION' ? `CORPORATION:${input.subjectId}` : 'EARTH';
    const policyGroup = input.actionType === 'EARTH_CAPACITY_POLICY' ? 'EARTH:CAPACITY_POLICY'
      : input.actionType === 'CORPORATION_HOUSE_RATE' ? `${scope}:HOUSE_CAPACITY_POLICY`
        : input.actionType === 'CORPORATION_ADMISSION_POLICY' ? `${scope}:ADMISSION_POLICY`
          : input.actionType === 'CONSTITUTION_AMENDMENT' ? `${scope}:${getConstitutionalRuleDefinition(String((action.changes ?? [])[0]?.ruleCode ?? 'CONSTITUTION')).policyGroup}`
            : `${scope}:PROGRESSIVE_SCHEDULE`;
    if ((await tx.query(`SELECT 1 FROM v5_governance_proposals WHERE subject_type = $1 AND subject_id IS NOT DISTINCT FROM $2 AND policy_group = $3 AND status IN ('VOTING','PASSED','SCHEDULED') LIMIT 1`, [input.subjectType, input.subjectId, policyGroup])).rows[0]) throw new Error('An active proposal already exists for this policy group');
    const governanceRuleSnapshot = await governancePolicy(tx, input.subjectType, input.subjectId, day);
    if (action.effectiveFromGameDay < day + 1 + governanceRuleSnapshot.implementationDelayDays) {
      throw new Error('Constitution amendment does not satisfy the implementation delay');
    }
    const votingStart = day + 1;
    const electorate = input.subjectType === 'CORPORATION'
      ? await tx.query<{ count: string }>(`SELECT COUNT(DISTINCT house_id)::TEXT AS count FROM house_affiliations WHERE corporation_id = $1 AND status = 'ACTIVE' AND joined_game_day <= $2 AND (left_game_day IS NULL OR left_game_day >= $2)`, [input.subjectId, votingStart])
      : await tx.query<{ count: string }>("SELECT COUNT(*)::TEXT AS count FROM houses WHERE status = 'ACTIVE'", []);
    const electorateSize = Number(electorate.rows[0]?.count ?? 0);
    const baseVersionSnapshot: Record<string, unknown> = { capturedAtGameDay: day };
    let proposalPayload = proposalInputPayload;
    if (input.actionType === 'CONSTITUTION_AMENDMENT') {
      const authorityType = input.subjectType;
      const authorityId = input.subjectType === 'EARTH' ? 'EARTH' : String(input.subjectId);
      const codes = (action.changes ?? []).map((change) => change.ruleCode);
      const currentVersions = (await tx.query<{ rule_code: string; id: string }>(`SELECT rule_code, id FROM constitutional_rule_versions_v5 WHERE authority_type = $1 AND authority_id = $2 AND status = 'ACTIVE' AND effective_to_game_day IS NULL AND rule_code = ANY($3::TEXT[])`, [authorityType, authorityId, codes])).rows;
      for (const code of codes) baseVersionSnapshot[code] = null;
      for (const version of currentVersions) baseVersionSnapshot[version.rule_code] = version.id;
      const changes = (action.changes ?? []).map((change) => ({ ...change, baseVersionId: change.baseVersionId ?? (baseVersionSnapshot[change.ruleCode] as string | undefined) }));
      // Persist exactly the payload that was validated. In particular, the
      // effective day may have been normalized above when a client supplied a
      // stale/past day; activation must never consume the pre-normalized copy.
      proposalPayload = { ...proposalInputPayload, changes };
    }
    const proposalId = `V5-GOV-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    const effective = action.effectiveFromGameDay;
    await tx.query(`INSERT INTO v5_governance_proposals (id, subject_type, subject_id, action_type, payload, status, submitted_game_day, voting_start_game_day, voting_end_game_day, effective_from_game_day, created_by_human_id, correlation_id, quorum_bps, approval_bps, electorate_snapshot_game_day, electorate_size, governance_rule_snapshot, base_version_snapshot, policy_group)
      VALUES ($1,$2,$3,$4,$5::JSONB,'VOTING',$6,$7,$7 + $13,$8,$9,$10,$11,$12,$7,$14,$15::JSONB,$16::JSONB,$17)`, [proposalId, input.subjectType, input.subjectId, input.actionType, JSON.stringify(proposalPayload), day, votingStart, effective, input.humanId, input.correlationId, governanceRuleSnapshot.quorumBps, governanceRuleSnapshot.approvalBps, governanceRuleSnapshot.votingPeriodDays, electorateSize, JSON.stringify(governanceRuleSnapshot), JSON.stringify(baseVersionSnapshot), policyGroup]);
    if (input.subjectType === 'CORPORATION') {
      await tx.query(
        `INSERT INTO v5_governance_electorate_snapshots_v5 (proposal_id, house_id, snapshot_game_day)
         SELECT $1, ha.house_id, $2
           FROM house_affiliations ha
          WHERE ha.corporation_id = $3
            AND ha.status = 'ACTIVE'
            AND ha.joined_game_day <= $2
            AND (ha.left_game_day IS NULL OR ha.left_game_day >= $2)`,
        [proposalId, votingStart, input.subjectId],
      );
    } else {
      await tx.query(
        `INSERT INTO v5_governance_electorate_snapshots_v5 (proposal_id, house_id, snapshot_game_day)
         SELECT $1, h.id, $2
           FROM houses h
          WHERE h.status = 'ACTIVE'`,
        [proposalId, votingStart],
      );
    }
    if (input.actionType === 'CONSTITUTION_AMENDMENT') await tx.query(`INSERT INTO constitutional_change_sets_v5 (proposal_id, authority_type, authority_id, policy_group, changes, base_version_snapshot) VALUES ($1,$2,$3,$4,$5::JSONB,$6::JSONB)`, [proposalId, input.subjectType, input.subjectType === 'EARTH' ? 'EARTH' : input.subjectId, policyGroup, JSON.stringify((proposalPayload as Record<string, unknown>).changes), JSON.stringify(baseVersionSnapshot)]);
    await createGameEvent(tx, { id: `V5-GOV-CREATED-${proposalId}`, category: 'GOVERNANCE', eventType: 'V5_POLICY_PROPOSAL_CREATED', gameDay: day, actorHumanId: input.humanId, subjectType: input.subjectType, subjectId: input.subjectId ?? 'EARTH', title: input.title.trim(), details: { proposalId, actionType: input.actionType, effectiveFromGameDay: effective, body: input.body?.trim() ?? '' }, correlationId: input.correlationId });
    return { ok: true, proposal: toJsonSafe((await tx.query('SELECT * FROM v5_governance_proposals WHERE id = $1', [proposalId])).rows[0]), correlationId: input.correlationId };
  });
}

export async function castV5GovernanceVote(repository: PostgresRepository, input: { humanId: string; proposalId: string; choice: 'SUPPORT' | 'OPPOSE' | 'ABSTAIN'; correlationId: string }) {
  return repository.transaction(async (tx) => {
    const proposal = (await tx.query<{ id: string; subject_type: 'EARTH' | 'CORPORATION'; subject_id: string | null; voting_start_game_day: number; voting_end_game_day: number; electorate_snapshot_game_day: number; status: string }>('SELECT id, subject_type, subject_id, voting_start_game_day, voting_end_game_day, electorate_snapshot_game_day, status FROM v5_governance_proposals WHERE id = $1 FOR UPDATE', [input.proposalId])).rows[0];
    if (!proposal || proposal.status !== 'VOTING') throw new Error('V5 governance proposal is not open for voting');
    const day = await currentDay(tx);
    if (day < proposal.voting_start_game_day || day > proposal.voting_end_game_day) throw new Error('V5 governance voting is not open');
    const houseId = await canVote(tx, input.humanId, proposal);
    await tx.query(`INSERT INTO v5_governance_ballots (proposal_id, house_id, cast_by_human_id, choice, cast_game_day, correlation_id) VALUES ($1,$2,$3,$4,$5,$6)
      ON CONFLICT (proposal_id, house_id) DO UPDATE SET choice = EXCLUDED.choice, cast_by_human_id = EXCLUDED.cast_by_human_id, cast_game_day = EXCLUDED.cast_game_day, correlation_id = EXCLUDED.correlation_id`, [input.proposalId, houseId, input.humanId, input.choice, day, input.correlationId]);
    const totals = (await tx.query<{ support: string; oppose: string; abstain: string }>(`SELECT COUNT(*) FILTER (WHERE choice = 'SUPPORT')::TEXT AS support, COUNT(*) FILTER (WHERE choice = 'OPPOSE')::TEXT AS oppose, COUNT(*) FILTER (WHERE choice = 'ABSTAIN')::TEXT AS abstain FROM v5_governance_ballots WHERE proposal_id = $1`, [input.proposalId])).rows[0];
    await tx.query('UPDATE v5_governance_proposals SET support_votes = $1, oppose_votes = $2, abstain_votes = $3 WHERE id = $4', [totals?.support ?? '0', totals?.oppose ?? '0', totals?.abstain ?? '0', input.proposalId]);
    return { ok: true, proposalId: input.proposalId, houseId, choice: input.choice, correlationId: input.correlationId };
  });
}

export async function resolveV5GovernanceProposal(repository: PostgresRepository, proposalId: string) {
  return repository.transaction(async (tx) => {
    const proposal = (await tx.query<any>('SELECT * FROM v5_governance_proposals WHERE id = $1 FOR UPDATE', [proposalId])).rows[0];
    if (!proposal) throw new Error('V5 governance proposal not found');
    if (proposal.status !== 'VOTING') return { ok: true, alreadyProcessed: true, proposal: toJsonSafe(proposal) };
    const day = await currentDay(tx);
    if (day <= Number(proposal.voting_end_game_day)) throw new Error('V5 governance voting period is still open');
    const support = Number(proposal.support_votes); const oppose = Number(proposal.oppose_votes); const abstain = Number(proposal.abstain_votes);
    const electorateSize = Number(proposal.electorate_size);
    const decision = evaluateOneHouseVote({ support, oppose, abstain, electorateSize, quorumBps: Number(proposal.quorum_bps), approvalBps: Number(proposal.approval_bps) });
    const { quorumMet, passed } = decision;
    const status = passed ? 'SCHEDULED' : 'REJECTED';
    await tx.query('UPDATE v5_governance_proposals SET status = $1, quorum_met = $2 WHERE id = $3', [passed ? 'PASSED' : status, quorumMet, proposalId]);
    if (passed) {
      await tx.query(`INSERT INTO v5_governance_activation_queue (proposal_id, action_type, payload, effective_from_game_day) VALUES ($1,$2,$3::JSONB,$4) ON CONFLICT (proposal_id) DO NOTHING`, [proposalId, proposal.action_type, JSON.stringify(proposal.payload), proposal.effective_from_game_day]);
      await tx.query("UPDATE v5_governance_proposals SET status = 'SCHEDULED' WHERE id = $1", [proposalId]);
    }
    return { ok: true, proposalId, status, quorumMet, supportVotes: support, opposeVotes: oppose, abstainVotes: abstain, effectiveFromGameDay: passed ? Number(proposal.effective_from_game_day) : null };
  });
}

async function retireActive(tx: PostgresRepository, table: string, keyColumn: string, keyValue: string, effective: number): Promise<void> {
  await tx.query(`UPDATE ${table} SET status = 'RETIRED' WHERE ${keyColumn} = $1 AND status = 'ACTIVE'`, [keyValue]);
  await tx.query(`UPDATE ${table} SET effective_to_game_day = $2 WHERE ${keyColumn} = $1 AND status = 'RETIRED' AND effective_to_game_day IS NULL`, [keyValue, effective - 1]);
}

function progressiveBasis(ruleCode: string): 'EARTH_CORPORATION_CAPACITY' | 'CORPORATION_HOUSE_CAPACITY' | 'HOUSE_INCOME_TAX' {
  if (ruleCode === 'EARTH.CAPACITY.PROGRESSIVE_SCHEDULE') return 'EARTH_CORPORATION_CAPACITY';
  if (ruleCode === 'EARTH.CAPACITY.HOUSE_PROGRESSIVE_SCHEDULE') return 'CORPORATION_HOUSE_CAPACITY';
  return 'HOUSE_INCOME_TAX';
}

async function materializeConstitutionSchedule(
  tx: PostgresRepository,
  input: { proposalId: string; ruleCode: string; authorityType: 'EARTH' | 'CORPORATION'; authorityId: string; effective: number; brackets: NonNullable<ProposalAction['brackets']> },
): Promise<string> {
  const scheduleId = `CONST-SCHEDULE-${input.proposalId}-${input.ruleCode.replaceAll('.', '-')}`;
  const code = `CONSTITUTION:${input.ruleCode}:${input.authorityId}`;
  const authority = (await tx.query<{ id: string }>(
    'SELECT id FROM institutions WHERE id = $1 AND status = \'ACTIVE\'',
    [input.authorityType === 'EARTH' ? 'EARTH' : input.authorityId],
  )).rows[0];
  if (!authority) throw new Error(`Constitution schedule authority is unavailable: ${input.authorityId}`);
  const version = Number((await tx.query<{ version: number }>(
    'SELECT COALESCE(MAX(version), 0) + 1 AS version FROM progressive_policy_schedules WHERE code = $1',
    [code],
  )).rows[0]?.version ?? 1);
  await tx.query(
    `INSERT INTO progressive_policy_schedules
       (id, code, basis_type, authority_institution_id, version, status, effective_from_game_day, created_by)
     VALUES ($1,$2,$3,$4,$5,'DRAFT',$6,NULL)`,
    [scheduleId, code, progressiveBasis(input.ruleCode), authority.id, version, input.effective],
  );
  for (const bracket of input.brackets) {
    await tx.query(
      `INSERT INTO progressive_policy_brackets
         (schedule_id, ordinal, lower_bound_units, upper_bound_units,
          marginal_multiplier_numerator, marginal_multiplier_denominator)
       VALUES ($1,$2,$3,$4,$5,$6)`,
      [scheduleId, bracket.ordinal, bracket.lowerBound.toString(), bracket.upperBound?.toString() ?? null, bracket.multiplierNumerator.toString(), bracket.multiplierDenominator.toString()],
    );
  }
  await tx.query('SELECT earth_validate_v5_progressive_schedule($1)', [scheduleId]);
  await tx.query("UPDATE progressive_policy_schedules SET status = 'ACTIVE' WHERE id = $1", [scheduleId]);
  return scheduleId;
}

async function applyActivation(tx: PostgresRepository, row: { proposal_id: string; action_type: string; payload: Record<string, unknown>; effective_from_game_day: number }, day: number): Promise<void> {
  const payload = row.payload;
  const effective = Number(row.effective_from_game_day);
  const action = actionFromPayload(row.action_type as ProposalAction['actionType'], payload);
  if (row.action_type === 'CONSTITUTION_AMENDMENT') {
    const proposal = (await tx.query<{ subject_type: 'EARTH' | 'CORPORATION'; subject_id: string | null }>('SELECT subject_type, subject_id FROM v5_governance_proposals WHERE id = $1', [row.proposal_id])).rows[0];
    if (!proposal) throw new Error('Constitution amendment proposal not found');
    const authorityType = proposal.subject_type;
    const authorityId = authorityType === 'EARTH' ? 'EARTH' : String(proposal.subject_id);
    const base = (await tx.query<{ base_version_snapshot: Record<string, string | null> }>('SELECT base_version_snapshot FROM constitutional_change_sets_v5 WHERE proposal_id = $1', [row.proposal_id])).rows[0]?.base_version_snapshot ?? {};
    for (const change of action.changes ?? []) {
      if (Object.prototype.hasOwnProperty.call(base, change.ruleCode)) {
        const current = (await tx.query<{ id: string }>(`SELECT id FROM constitutional_rule_versions_v5 WHERE rule_code = $1 AND authority_type = $2 AND authority_id = $3 AND status = 'ACTIVE' AND effective_to_game_day IS NULL`, [change.ruleCode, authorityType, authorityId])).rows[0];
        if ((current?.id ?? null) !== base[change.ruleCode]) throw new Error(`STALE constitutional amendment: ${change.ruleCode}`);
      }
      if (change.clearOverride) {
        await tx.query(`UPDATE constitutional_rule_versions_v5 SET status = 'RETIRED', effective_to_game_day = $3 WHERE rule_code = $1 AND authority_type = 'CORPORATION' AND authority_id = $2 AND status = 'ACTIVE' AND effective_to_game_day IS NULL`, [change.ruleCode, authorityId, effective - 1]);
        continue;
      }
      let constitutionalValue = change.value;
      const definition = getConstitutionalRuleDefinition(change.ruleCode);
      if (definition.valueType === 'PROGRESSIVE_SCHEDULE_REF' && Array.isArray(change.value)) {
        constitutionalValue = await materializeConstitutionSchedule(tx, {
          proposalId: row.proposal_id,
          ruleCode: change.ruleCode,
          authorityType,
          authorityId,
          effective,
          brackets: change.value as NonNullable<ProposalAction['brackets']>,
        });
      }
      const prior = (await tx.query<{ version: number }>('SELECT COALESCE(MAX(version), 0) + 1 AS version FROM constitutional_rule_versions_v5 WHERE rule_code = $1 AND authority_type = $2 AND authority_id = $3', [change.ruleCode, authorityType, authorityId])).rows[0];
      await tx.query(`UPDATE constitutional_rule_versions_v5 SET status = 'RETIRED', effective_to_game_day = $4 WHERE rule_code = $1 AND authority_type = $2 AND authority_id = $3 AND status = 'ACTIVE' AND effective_to_game_day IS NULL`, [change.ruleCode, authorityType, authorityId, effective - 1]);
      await tx.query(`INSERT INTO constitutional_rule_versions_v5 (id, rule_code, authority_type, authority_id, version, value_json, effective_from_game_day, status, proposal_id) VALUES ($1,$2,$3,$4,$5,$6::JSONB,$7,'ACTIVE',$8)`, [`CONST-${row.proposal_id}-${change.ruleCode}`, change.ruleCode, authorityType, authorityId, Number(prior?.version ?? 1), JSON.stringify({ value: constitutionalValue }), effective, row.proposal_id]);
      if (change.ruleCode === 'CORPORATION.ADMISSION_POLICY' && authorityType === 'CORPORATION') {
        await tx.query('UPDATE corporations SET admission_policy = $1 WHERE id = $2', [String(change.value), authorityId]);
      }
    }
  } else if (row.action_type === 'CORPORATION_ADMISSION_POLICY') {
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
  await tx.query("UPDATE v5_governance_proposals SET status = 'ACTIVATED' WHERE id = $1", [row.proposal_id]);
}

export async function activateDueV5GovernancePoliciesInTransaction(tx: PostgresRepository, day: number) {
  const rows = (await tx.query<{ proposal_id: string; action_type: string; payload: Record<string, unknown>; effective_from_game_day: number }>(`SELECT proposal_id, action_type, payload, effective_from_game_day FROM v5_governance_activation_queue WHERE status = 'PENDING' AND effective_from_game_day <= $1 ORDER BY effective_from_game_day, proposal_id FOR UPDATE`, [day])).rows;
  let applied = 0; let failed = 0;
  for (const row of rows) {
    const savepoint = `v5_activation_${row.proposal_id.replace(/[^a-zA-Z0-9_]/g, '_')}`;
    await tx.query(`SAVEPOINT ${savepoint}`);
    try {
      await applyActivation(tx, row, day);
      await tx.query(`RELEASE SAVEPOINT ${savepoint}`);
      applied += 1;
    } catch (error) {
      // A Constitution change set is atomic. Restore every rule/schedule write
      // from this proposal before recording its terminal failure state.
      await tx.query(`ROLLBACK TO SAVEPOINT ${savepoint}`);
      await tx.query(`RELEASE SAVEPOINT ${savepoint}`);
      failed += 1;
      const message = error instanceof Error ? error.message : 'Activation failed';
      const stale = message.startsWith('STALE');
      await tx.query(`UPDATE v5_governance_activation_queue SET status = $2, error_message = $3 WHERE proposal_id = $1`, [row.proposal_id, stale ? 'STALE' : 'FAILED', message]);
      if (stale) await tx.query("UPDATE v5_governance_proposals SET status = 'STALE' WHERE id = $1", [row.proposal_id]);
    }
  }
  return { ok: true, day, applied, failed };
}
