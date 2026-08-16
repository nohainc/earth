import type { PostgresRepository } from './repository';

export function politicalMaturityReached(currentGameDay: number, eligibilityGameDay: number): boolean {
  return Number.isFinite(currentGameDay) && Number.isFinite(eligibilityGameDay) && currentGameDay >= eligibilityGameDay;
}

async function eligible(tx: PostgresRepository, humanId: string, institutionId: string): Promise<boolean> {
  const institution = await tx.query<{ kind: string; status: string }>('SELECT kind, status FROM institutions WHERE id = $1', [institutionId]);
  if (!institution.rows[0] || institution.rows[0].status !== 'active') return false;
  const maturity = await tx.query<{ game_day: number; political_eligibility_game_day: number }>("SELECT w.game_day, h.political_eligibility_game_day FROM world_state w JOIN humans h ON h.id = $1 WHERE w.id = 'WORLD' AND h.life_status = 'active'", [humanId]);
  if (!maturity.rows[0] || !politicalMaturityReached(Number(maturity.rows[0].game_day), Number(maturity.rows[0].political_eligibility_game_day ?? 0))) return false;
  if (institution.rows[0].kind === 'CORPORATION') return Boolean((await tx.query('SELECT 1 FROM memberships WHERE human_id = $1 AND corporation_id = $2', [humanId, institutionId])).rows[0]);
  if (institution.rows[0].kind === 'CITY') return Boolean((await tx.query('SELECT 1 FROM memberships WHERE human_id = $1 AND city_id = $2', [humanId, institutionId])).rows[0]);
  return Boolean((await tx.query("SELECT 1 FROM role_assignments WHERE human_id = $1 AND institution_id = $2 AND status = 'active' AND ends_game_day > (SELECT game_day FROM world_state WHERE id = 'WORLD') UNION ALL SELECT 1 FROM authority_delegations WHERE delegate_id = $1 AND institution_id = $2 AND status = 'active' AND ends_game_day > (SELECT game_day FROM world_state WHERE id = 'WORLD') LIMIT 1", [humanId, institutionId])).rows[0]);
}

function jsonObject(value: unknown): Record<string, unknown> {
  if (value && typeof value === 'object') return value as Record<string, unknown>;
  if (typeof value === 'string') {
    try { return JSON.parse(value) as Record<string, unknown>; } catch (_error) { return {}; }
  }
  return {};
}

export async function createProposal(repository: PostgresRepository, input: { humanId: string; institutionId: string; title: string; body: string; durationHours: number; ruleVersionId?: string; targetCategory: string | null; targetValue: Record<string, unknown> | null; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query('SELECT * FROM proposals WHERE institution_id = $1 AND correlation_id = $2', [input.institutionId, input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, proposal: prior.rows[0], correlationId: input.correlationId };
    if (!(await eligible(tx, input.humanId, input.institutionId))) throw new Error('Human is not eligible to propose at this institution');
    const rule = input.ruleVersionId
      ? await tx.query<{ value_json: unknown; id: string }>("SELECT id, value_json FROM governance_rules WHERE id = $1 AND institution_id = $2 AND status = 'active'", [input.ruleVersionId, input.institutionId])
      : await tx.query<{ value_json: unknown; id: string }>("SELECT id, value_json FROM governance_rules WHERE institution_id = $1 AND status = 'active' ORDER BY version DESC LIMIT 1", [input.institutionId]);
    if (!rule.rows[0]) throw new Error('An active governance rule version is required');
    const config = jsonObject(rule.rows[0].value_json);
    const quorum = Number(config.quorum ?? 0.25);
    const approvalThreshold = Number(config.approvalThreshold ?? 0.5);
    const implementationDelay = Number(config.implementationDelayDays ?? 1);
    if (!(quorum > 0 && quorum <= 1) || !(approvalThreshold > 0 && approvalThreshold <= 1) || !Number.isInteger(implementationDelay) || implementationDelay < 0 || implementationDelay > 30) throw new Error('Governance rule parameters are invalid');
    const proposalId = `P-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    const world = await tx.query<{ game_day: number; game_minute: number }>("SELECT game_day, game_minute FROM world_state WHERE id = 'WORLD' FOR UPDATE");
    const currentAbsoluteMinute = Number(world.rows[0]?.game_day ?? 0) * 1440 + Number(world.rows[0]?.game_minute ?? 0);
    const closesAbsoluteMinute = currentAbsoluteMinute + input.durationHours * 60;
    const implementationAbsoluteMinute = closesAbsoluteMinute + implementationDelay * 1440;
    const closesGameDay = Math.floor(closesAbsoluteMinute / 1440);
    const closesGameMinute = closesAbsoluteMinute % 1440;
    const implementationGameDay = Math.floor(implementationAbsoluteMinute / 1440);
    const implementationGameMinute = implementationAbsoluteMinute % 1440;
    await tx.query("INSERT INTO proposals (id, institution_id, title, body, status, opens_at, closes_at, closes_game_day, closes_game_minute, rule_version_id, quorum, approval_threshold, implementation_delay_days, implementation_at, implementation_game_day, implementation_game_minute, target_category, target_value_json, correlation_id) VALUES ($1,$2,$3,$4,'open',CURRENT_TIMESTAMP,CURRENT_TIMESTAMP + ($5 * INTERVAL '1 hour'),$6,$7,$8,$9,$10,$11,CURRENT_TIMESTAMP + (($5 + $11 * 24) * INTERVAL '1 hour'),$12,$13,$14,$15,$16)", [proposalId, input.institutionId, input.title, input.body, input.durationHours, closesGameDay, closesGameMinute, rule.rows[0].id, quorum, approvalThreshold, implementationDelay, implementationGameDay, implementationGameMinute, input.targetCategory, input.targetValue ? JSON.stringify(input.targetValue) : null, input.correlationId]);
    return { ok: true, proposal: (await tx.query('SELECT * FROM proposals WHERE id = $1', [proposalId])).rows[0], createdBy: input.humanId, correlationId: input.correlationId };
  });
}

export async function castVote(repository: PostgresRepository, input: { proposalId: string; humanId: string; choice: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const proposal = await tx.query<{ institution_id: string }>("SELECT p.institution_id FROM proposals p CROSS JOIN world_state w WHERE p.id = $1 AND p.status = 'open' AND (p.closes_game_day, p.closes_game_minute) > (w.game_day, w.game_minute) AND w.id = 'WORLD'", [input.proposalId]);
    if (!proposal.rows[0]) throw new Error('Open proposal not found');
    if (!(await eligible(tx, input.humanId, proposal.rows[0].institution_id))) throw new Error('Human is not eligible to vote at this institution');
    const representation = await tx.query<{ member_count: string | null; residents: string | null }>('SELECT corporations.member_count, cities.residents FROM memberships LEFT JOIN corporations ON corporations.id = memberships.corporation_id LEFT JOIN cities ON cities.id = memberships.city_id WHERE memberships.human_id = $1 LIMIT 1', [input.humanId]);
    const population = Number(representation.rows[0]?.member_count ?? representation.rows[0]?.residents ?? 0);
    const weight = Math.round((1 + Math.min(2, population / 100)) * 1000) / 1000;
    try {
      await tx.query('INSERT INTO ballots (proposal_id, human_id, choice, weight) VALUES ($1,$2,$3,$4)', [input.proposalId, input.humanId, input.choice, weight]);
    } catch (_error) {
      throw new Error('Ballot already recorded');
    }
    const counts = await tx.query('SELECT choice, ROUND(SUM(weight), 3) AS count FROM ballots WHERE proposal_id = $1 GROUP BY choice', [input.proposalId]);
    return { ok: true, proposalId: input.proposalId, humanId: input.humanId, vote: input.choice, weight, counts: counts.rows };
  });
}

export async function resolveProposals(repository: PostgresRepository): Promise<number> {
  await repository.query("UPDATE proposals p SET status = 'closed' FROM world_state w WHERE w.id = 'WORLD' AND p.status = 'open' AND (p.closes_game_day, p.closes_game_minute) <= (w.game_day, w.game_minute)");
  const closed = await repository.query<{ id: string; quorum: string; approval_threshold: string }>("SELECT id, quorum, approval_threshold FROM proposals WHERE status = 'closed' AND outcome = 'pending'");
  let resolved = 0;
  for (const proposal of closed.rows) {
    await repository.transaction(async (tx) => {
      const counts = await tx.query<{ choice: string; weight: string }>('SELECT choice, COALESCE(SUM(weight), 0) AS weight FROM ballots WHERE proposal_id = $1 GROUP BY choice', [proposal.id]);
      const totals = Object.fromEntries(counts.rows.map((row) => [row.choice, Number(row.weight)]));
      const eligibleHumans = await tx.query<{ count: string }>("SELECT COUNT(*) AS count FROM humans WHERE life_status = 'active'");
      const cast = (totals.support ?? 0) + (totals.oppose ?? 0) + (totals.abstain ?? 0);
      const decisive = (totals.support ?? 0) + (totals.oppose ?? 0);
      const eligibleWeight = Math.max(1, Number(eligibleHumans.rows[0]?.count ?? 0));
      const quorumMet = cast / eligibleWeight >= Number(proposal.quorum);
      const passed = quorumMet && decisive > 0 && (totals.support ?? 0) / decisive >= Number(proposal.approval_threshold);
      const outcome = !quorumMet ? 'no_quorum' : passed ? 'passed' : 'rejected';
      await tx.query("UPDATE proposals SET outcome = $1, resolved_at = CURRENT_TIMESTAMP, implementation_at = CASE WHEN $2 = 'passed' THEN CURRENT_TIMESTAMP + (implementation_delay_days * INTERVAL '1 day') ELSE NULL END, execution_status = CASE WHEN $2 = 'passed' THEN 'ready' ELSE 'not_ready' END WHERE id = $3 AND outcome = 'pending'", [outcome, outcome, proposal.id]);
    });
    resolved += 1;
  }
  return resolved;
}

export async function executeProposal(repository: PostgresRepository, input: { proposalId: string; humanId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const proposal = await tx.query<{ id: string; institution_id: string; title: string; outcome: string; executed_at: string | null; implementation_game_day: number | null; implementation_game_minute: number | null; target_category: string | null; target_value_json: unknown; execution_status: string }>('SELECT * FROM proposals WHERE id = $1 FOR UPDATE', [input.proposalId]);
    if (!proposal.rows[0]) throw new Error('Proposal not found');
    const current = proposal.rows[0];
    if (current.outcome !== 'passed') throw new Error('Only passed proposals can be executed');
    if (current.executed_at) return { ok: true, executionStatus: 'executed', proposal: current };
    if (current.execution_status === 'challenged') throw new Error('Proposal is currently under constitutional challenge and cannot be executed');
    if (current.execution_status === 'voided') throw new Error('Proposal has been voided by constitutional appeal');
    const world = await tx.query<{ game_day: number; game_minute: number }>("SELECT game_day, game_minute FROM world_state WHERE id = 'WORLD'");
    if (current.implementation_game_day !== null && (Number(world.rows[0]?.game_day ?? 0) * 1440 + Number(world.rows[0]?.game_minute ?? 0)) < (Number(current.implementation_game_day) * 1440 + Number(current.implementation_game_minute ?? 0))) throw new Error('Implementation delay has not elapsed');
    if (!(await eligible(tx, input.humanId, current.institution_id))) throw new Error('Human is not authorized to execute this institution rule');
    const category = String(current.target_category ?? '').trim();
    const value = jsonObject(current.target_value_json);
    if (!category || !Object.keys(value).length) {
      await tx.query("UPDATE proposals SET executed_at = CURRENT_TIMESTAMP, execution_status = 'skipped' WHERE id = $1", [current.id]);
      return { ok: true, executionStatus: 'skipped', reason: 'Proposal has no target rule payload', proposal: (await tx.query('SELECT * FROM proposals WHERE id = $1', [current.id])).rows[0] };
    }
    if (!['market', 'finance', 'services', 'technology'].includes(category)) throw new Error('Target rule is outside engine bounds');
    if (category === 'finance' && value.rate !== undefined && (typeof value.rate !== 'number' || Number(value.rate) < 0 || Number(value.rate) > 0.25)) throw new Error('Finance rule rate must be between 0 and 0.25');
    const previous = await tx.query<{ version: number }>('SELECT version FROM governance_rules WHERE institution_id = $1 AND category = $2 ORDER BY version DESC LIMIT 1', [current.institution_id, category]);
    const version = Number(previous.rows[0]?.version ?? 0) + 1;
    const ruleId = `RULE-${current.institution_id}-${category}-${version}`;
    await tx.query('INSERT INTO governance_rules (id, institution_id, name, category, value_json, version, status, created_by) VALUES ($1,$2,$3,$4,$5,$6,\'active\',$7)', [ruleId, current.institution_id, current.title, category, JSON.stringify(value), version, input.humanId]);
    await tx.query("UPDATE governance_rules SET status = 'superseded' WHERE institution_id = $1 AND category = $2 AND status = 'active' AND id <> $3", [current.institution_id, category, ruleId]);
    await tx.query("UPDATE proposals SET executed_at = CURRENT_TIMESTAMP, execution_status = 'executed' WHERE id = $1", [current.id]);
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), Number(world.rows[0]?.game_day ?? 0), 'rule.changed', `Rule ${category} changed`, JSON.stringify({ proposalId: current.id, ruleId })]);
    return { ok: true, executionStatus: 'executed', rule: (await tx.query('SELECT * FROM governance_rules WHERE id = $1', [ruleId])).rows[0], proposal: (await tx.query('SELECT * FROM proposals WHERE id = $1', [current.id])).rows[0] };
  });
}

export async function challengeProposal(repository: PostgresRepository, input: { humanId: string; proposalId: string; reason: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ details: string }>("SELECT details FROM world_events WHERE event_type = 'governance.challenge_filed' AND details->>'correlationId' = $1", [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, proposalId: input.proposalId, correlationId: input.correlationId };
    const proposal = await tx.query<{ id: string; institution_id: string; outcome: string; executed_at: string | null; execution_status: string }>('SELECT id, institution_id, outcome, executed_at, execution_status FROM proposals WHERE id = $1 FOR UPDATE', [input.proposalId]);
    if (!proposal.rows[0]) throw new Error('Proposal not found');
    if (proposal.rows[0].outcome !== 'passed') throw new Error('Only passed proposals can be challenged');
    if (proposal.rows[0].executed_at) throw new Error('Proposal has already been executed');
    if (!(await eligible(tx, input.humanId, proposal.rows[0].institution_id))) throw new Error('Human is not authorized to challenge this proposal');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    await tx.query("UPDATE proposals SET execution_status = 'challenged' WHERE id = $1", [input.proposalId]);
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), day, 'governance.challenge_filed', `Constitutional challenge filed for proposal ${input.proposalId}`, JSON.stringify({ proposalId: input.proposalId, challenger: input.humanId, reason: input.reason, correlationId: input.correlationId })]);
    return { ok: true, proposalId: input.proposalId, executionStatus: 'challenged', reason: input.reason, correlationId: input.correlationId };
  });
}

export async function resolveConstitutionalAppeal(repository: PostgresRepository, input: { humanId: string; proposalId: string; ruling: 'uphold' | 'void'; rationale: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ details: string }>("SELECT details FROM world_events WHERE event_type = 'governance.ruling_issued' AND details->>'correlationId' = $1", [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, proposalId: input.proposalId, ruling: input.ruling, correlationId: input.correlationId };
    const proposal = await tx.query<{ id: string; institution_id: string; outcome: string; executed_at: string | null }>('SELECT id, institution_id, outcome, executed_at FROM proposals WHERE id = $1 FOR UPDATE', [input.proposalId]);
    if (!proposal.rows[0]) throw new Error('Proposal not found');
    if (proposal.rows[0].executed_at) throw new Error('Proposal has already been executed');
    if (!(await eligible(tx, input.humanId, proposal.rows[0].institution_id))) throw new Error('Human is not authorized as a judicial delegate');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    if (input.ruling === 'void') {
      await tx.query("UPDATE proposals SET outcome = 'rejected', execution_status = 'skipped' WHERE id = $1", [input.proposalId]);
    } else {
      await tx.query("UPDATE proposals SET execution_status = 'ready' WHERE id = $1", [input.proposalId]);
    }
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), day, 'governance.ruling_issued', `Constitutional ruling for proposal ${input.proposalId}: ${input.ruling.toUpperCase()}`, JSON.stringify({ proposalId: input.proposalId, jurist: input.humanId, ruling: input.ruling, rationale: input.rationale, correlationId: input.correlationId })]);
    return { ok: true, proposalId: input.proposalId, ruling: input.ruling, executionStatus: input.ruling === 'void' ? 'voided' : 'ready', rationale: input.rationale, correlationId: input.correlationId };
  });
}
