import type { PostgresRepository } from './repository';
import { enqueueOutbox } from './outbox-postgres.ts';
import { toNanoMarkup, fromNanoMarkup } from './nano-markup.ts';
import { BUILDING_CATALOG } from './real-estate-catalog.ts';
import { transferCredits } from './financial-postgres.ts';
import { moneyToCents, centsToMoney } from './money.ts';
import { getAuthoritativeGameTime } from './game-clock.ts';
import { startCorporationBuildingResearchInTransaction } from './corporation-building-research-postgres.ts';

export function politicalMaturityReached(currentGameDay: number, eligibilityGameDay: number): boolean {
  return Number.isFinite(currentGameDay) && Number.isFinite(eligibilityGameDay) && currentGameDay >= eligibilityGameDay;
}

async function eligible(tx: PostgresRepository, humanId: string, institutionId: string): Promise<boolean> {
  const institution = await tx.query<{ id: string; kind: string; status: string }>(
    'SELECT kind, status FROM institutions WHERE id = $1',
    [institutionId],
  ).catch(async () => ({ rows: [] })).then(async (res) => {
    if (res.rows[0]) return res;
    return tx.query<{ id: string; kind: string; status: string }>(
      'SELECT i.id, i.kind, i.status FROM institutions i LEFT JOIN cities c ON c.institution_id = i.id WHERE i.id = $1 OR c.id = $1 LIMIT 1',
      [institutionId],
    ).catch(() => ({ rows: [] }));
  });
  if (!institution.rows[0] || institution.rows[0].status !== 'active') return false;

  const human = await tx.query<{ id: string; life_status: string }>(
    "SELECT id, life_status FROM humans WHERE id = $1 AND life_status = 'active' AND account_status = 'active'",
    [humanId],
  );
  if (!human.rows[0]) return false;

  const instId = institution.rows[0].id ?? institutionId;
  if (institution.rows[0].kind === 'CORPORATION') {
    return Boolean((await tx.query('SELECT 1 FROM memberships WHERE human_id = $1 AND (corporation_id = $2 OR corporation_id = $3)', [humanId, institutionId, instId])).rows[0]);
  }
  if (institution.rows[0].kind === 'CITY') {
    const membership = await tx.query<{ city_id: string | null }>('SELECT city_id FROM memberships WHERE human_id = $1', [humanId]);
    if (membership.rows[0]?.city_id) {
      return membership.rows[0].city_id === institutionId || membership.rows[0].city_id === instId;
    }
    await tx.query(
      'INSERT INTO memberships (human_id, city_id) VALUES ($1, $2) ON CONFLICT (human_id) DO UPDATE SET city_id = COALESCE(memberships.city_id, EXCLUDED.city_id)',
      [humanId, instId],
    );
    return true;
  }
  return Boolean((await tx.query("SELECT 1 FROM institutions WHERE id = $1 AND administrator_human_id = $2 AND status = 'active'", [institutionId, humanId])).rows[0]);
}

function jsonObject(value: unknown): Record<string, unknown> {
  if (value && typeof value === 'object') return value as Record<string, unknown>;
  if (typeof value === 'string') {
    try { return fromNanoMarkup<Record<string, unknown>>(value); } catch (_error) { return {}; }
  }
  return {};
}

const COMMON_GOVERNANCE_DEFAULTS = {
  quorum: 0.25,
  approvalThreshold: 0.50,
  votingPeriodDays: 3,
  implementationDelayDays: 0,
};

function absoluteMinute(gameDay: number, gameMinute: number): number {
  // Game days are 1-based; day 1 minute 0 is the beginning of the world clock.
  return Math.max(0, (Math.max(1, gameDay) - 1) * 1440 + Math.max(0, gameMinute));
}

function gamePosition(totalMinutes: number): { day: number; minute: number } {
  const safeMinutes = Math.max(0, Math.floor(totalMinutes));
  return { day: Math.floor(safeMinutes / 1440) + 1, minute: safeMinutes % 1440 };
}

export async function createProposal(repository: PostgresRepository, input: { humanId: string; institutionId: string; title: string; body: string; durationHours?: number; ruleVersionId?: string; targetCategory: string | null; targetValue: Record<string, unknown> | null; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query('SELECT * FROM proposals WHERE institution_id = $1 AND correlation_id = $2', [input.institutionId, input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, proposal: prior.rows[0], correlationId: input.correlationId };
    if (input.targetCategory === 'megaproject_procurement' && input.targetValue?.buildingType) {
      await tx.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`${input.institutionId}:megaproject_procurement:${String(input.targetValue.buildingType)}`]);
      const existing = await tx.query<{ id: string; title: string; status: string; outcome: string | null; execution_status: string | null; target_value_json: unknown }>(
        "SELECT id, title, status, outcome, execution_status, target_value_json FROM proposals WHERE institution_id = $1 AND target_category = 'megaproject_procurement' AND executed_at IS NULL AND (status IN ('open', 'pending') OR outcome = 'passed' OR execution_status IN ('ready', 'queued')) ORDER BY updated_at DESC",
        [input.institutionId],
      );
      const duplicate = existing.rows.find((proposal) => jsonObject(proposal.target_value_json).buildingType === input.targetValue?.buildingType);
      if (duplicate) throw new Error('A civic proposal for this building is already active or queued. No duplicate proposal was created.');

      if (input.targetValue.buildingType === 'urban-district-module') {
        const popRes = await tx.query<{ count: string }>('SELECT COUNT(*)::integer AS count FROM memberships WHERE city_id = $1', [input.institutionId]);
        const distRes = await tx.query<{ count: string }>("SELECT COUNT(*)::integer AS count FROM buildings WHERE city_id = $1 AND building_type = 'urban-district-module' AND status NOT IN ('closed', 'foreclosed')", [input.institutionId]);
        const population = Number(popRes.rows[0]?.count ?? 1);
        const districtCount = Math.max(1, Number(distRes.rows[0]?.count || 1));
        const maxCapacity = districtCount * 10;
        const requiredPopulation = Math.ceil(maxCapacity * 0.80);
        if (population < requiredPopulation) {
          throw new Error(`Urban District expansion requires the city to reach at least 80% citizen capacity (${population}/${maxCapacity} citizens, requires ${requiredPopulation}).`);
        }
      }
    }
    if (!(await eligible(tx, input.humanId, input.institutionId))) throw new Error('Human is not eligible to propose at this institution');
    const rule = input.ruleVersionId
      ? await tx.query<{ id: string; quorum_threshold: string | null; approval_threshold: string | null; voting_period_days: number | null; implementation_delay_days: number | null }>("SELECT id, quorum_threshold, approval_threshold, voting_period_days, implementation_delay_days FROM governance_rules WHERE id = $1 AND institution_id = $2 AND status = 'active'", [input.ruleVersionId, input.institutionId])
      : await tx.query<{ id: string; quorum_threshold: string | null; approval_threshold: string | null; voting_period_days: number | null; implementation_delay_days: number | null }>("SELECT id, quorum_threshold, approval_threshold, voting_period_days, implementation_delay_days FROM governance_rules WHERE institution_id = $1 AND status = 'active' ORDER BY version DESC LIMIT 1", [input.institutionId]);
    let ruleRow = rule.rows[0];
    if (!ruleRow) {
      const inst = await tx.query<{ name: string }>("SELECT name FROM institutions WHERE id = $1", [input.institutionId]);
      const instName = inst.rows[0]?.name ?? input.institutionId;
      const baselineId = `GOV-${input.institutionId}-BASELINE-v1`;
      await tx.query(
        `INSERT INTO governance_rules (
          id, institution_id, name, category, quorum_threshold, approval_threshold,
          voting_period_days, implementation_delay_days, version, status, created_by
        ) VALUES ($1, $2, $3, 'governance', $4, $5, $6, $7, 1, 'active', $8)
        ON CONFLICT (id) DO UPDATE SET status = 'active'`,
        [baselineId, input.institutionId, `${instName} Governance Baseline`, COMMON_GOVERNANCE_DEFAULTS.quorum, COMMON_GOVERNANCE_DEFAULTS.approvalThreshold, COMMON_GOVERNANCE_DEFAULTS.votingPeriodDays, COMMON_GOVERNANCE_DEFAULTS.implementationDelayDays, input.humanId],
      );
      const inserted = await tx.query<{ id: string; quorum_threshold: string | null; approval_threshold: string | null; voting_period_days: number | null; implementation_delay_days: number | null }>(
        "SELECT id, quorum_threshold, approval_threshold, voting_period_days, implementation_delay_days FROM governance_rules WHERE id = $1",
        [baselineId],
      );
      ruleRow = inserted.rows[0];
    }
    if (!ruleRow) throw new Error('An active governance rule version is required');
    const quorum = Number(ruleRow.quorum_threshold);
    const approvalThreshold = Number(ruleRow.approval_threshold);
    const votingPeriodDays = Number(ruleRow.voting_period_days ?? COMMON_GOVERNANCE_DEFAULTS.votingPeriodDays);
    const implementationDelay = Number(ruleRow.implementation_delay_days ?? COMMON_GOVERNANCE_DEFAULTS.implementationDelayDays);
    if (!(quorum > 0 && quorum <= 1) || !(approvalThreshold > 0 && approvalThreshold <= 1) || !Number.isInteger(votingPeriodDays) || votingPeriodDays < 1 || votingPeriodDays > 90 || !Number.isInteger(implementationDelay) || implementationDelay < 0 || implementationDelay > 30) throw new Error('Governance rule parameters are invalid');
    const proposalId = `P-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    const world = await tx.query<{ genesis_at: string | null }>("SELECT genesis_at FROM world_state WHERE id = 'WORLD' FOR UPDATE");
    const currentGameDay = getAuthoritativeGameTime({
      genesisAt: world.rows[0]?.genesis_at,
    }).gameDay;
    // A submission never receives a partial voting day. Voting starts tomorrow
    // and its final whole day closes during end-of-day automation.
    const votingStartDay = currentGameDay + 1;
    const votingDueEndDay = votingStartDay + votingPeriodDays - 1;
    const implementationDueEndDay = votingDueEndDay + implementationDelay;
    let targetKind = 'generic';
    let buildingCatalogId: string | null = null;
    let researchProjectId: string | null = null;

    if (input.targetCategory === 'megaproject_procurement' || input.targetCategory === 'building') {
      const buildingType = String(input.targetValue?.buildingCatalogId ?? input.targetValue?.building_catalog_id ?? input.targetValue?.buildingType ?? input.targetValue?.type ?? '');
      if (buildingType) {
        const buildingTarget = await tx.query<{ id: string }>(
          `SELECT id FROM building_catalog WHERE id = $1 OR building_type = $1 ORDER BY tier ASC LIMIT 1`,
          [buildingType],
        );
        if (buildingTarget.rows[0]) {
          targetKind = 'building_catalog';
          buildingCatalogId = buildingTarget.rows[0].id;
        }
      }
    } else if (input.targetCategory === 'technology' || input.targetCategory === 'research') {
      const researchKey = String(input.targetValue?.researchProjectId ?? input.targetValue?.research_project_id ?? input.targetValue?.projectId ?? input.targetValue?.technologyKey ?? input.targetValue?.technology ?? '');
      if (researchKey) {
        const researchTarget = await tx.query<{ id: string }>(
          `SELECT id FROM corporation_building_research_projects WHERE id = $1 OR catalog_id = $1 OR building_type = $1 ORDER BY created_at DESC LIMIT 1`,
          [researchKey],
        );
        if (researchTarget.rows[0]) {
          targetKind = 'research_project';
          researchProjectId = researchTarget.rows[0].id;
        }
      }
    } else if (['finance', 'market', 'tax'].includes(input.targetCategory ?? '')) {
      targetKind = 'finance_rule';
    }

    await tx.query(
      `INSERT INTO proposals (
        id, institution_id, title, body, status, opens_at, opens_game_day,
        opens_game_minute, closes_at,
        closes_game_day, closes_game_minute, rule_version_id, quorum,
        approval_threshold, implementation_delay_days, implementation_at,
        implementation_game_day, implementation_game_minute,
        target_category, target_value_json, target_kind, building_catalog_id,
        research_project_id, correlation_id, created_by_human_id,
        submitted_game_day, voting_start_day, voting_duration_days, voting_due_end_day, implementation_due_end_day
      ) VALUES ($1,$2,$3,$4,'scheduled',CURRENT_TIMESTAMP,$5,0,CURRENT_TIMESTAMP,$6,0,$7,$8,$9,$10,CURRENT_TIMESTAMP,$11,0,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23)`,
      [
        proposalId,
        input.institutionId,
        input.title,
        input.body,
        currentGameDay,
        votingDueEndDay,
        ruleRow.id,
        quorum,
        approvalThreshold,
        implementationDelay,
        implementationDueEndDay,
        input.targetCategory,
        input.targetValue ? toNanoMarkup(input.targetValue) : null,
        targetKind,
        buildingCatalogId,
        researchProjectId,
        input.correlationId,
        input.humanId,
        currentGameDay,
        votingStartDay,
        votingPeriodDays,
        votingDueEndDay,
        implementationDueEndDay,
      ],
    );
    return { ok: true, proposal: (await tx.query('SELECT p.*, h.display_name AS creator_name FROM proposals p LEFT JOIN humans h ON h.id = p.created_by_human_id WHERE p.id = $1', [proposalId])).rows[0], createdBy: input.humanId, correlationId: input.correlationId };
  });
}

export async function castVote(repository: PostgresRepository, input: { proposalId: string; humanId: string; choice: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const proposal = await tx.query<{ institution_id: string; voting_due_end_day: number }>("SELECT institution_id, voting_due_end_day FROM proposals WHERE id = $1 AND status = 'open'", [input.proposalId]);
    if (!proposal.rows[0]) throw new Error('Open proposal not found');
    const world = await tx.query<{ genesis_at: string | null }>("SELECT genesis_at FROM world_state WHERE id = 'WORLD'");
    const now = getAuthoritativeGameTime({ genesisAt: world.rows[0]?.genesis_at });
    if (now.gameDay > Number(proposal.rows[0].voting_due_end_day)) throw new Error('Voting deadline has passed');
    if (!(await eligible(tx, input.humanId, proposal.rows[0].institution_id))) throw new Error('Human is not eligible to vote at this institution');
    const representation = await tx.query<{ member_count: string | null; residents: string | null }>('SELECT corporations.member_count, cities.residents FROM memberships LEFT JOIN corporations ON corporations.id = memberships.corporation_id LEFT JOIN cities ON cities.id = memberships.city_id WHERE memberships.human_id = $1 LIMIT 1', [input.humanId]);
    const population = Number(representation.rows[0]?.member_count ?? representation.rows[0]?.residents ?? 0);
    const diplomaticPerk = await tx.query("SELECT 1 FROM auth_credentials ac JOIN houses h ON h.email = ac.email JOIN house_perks hp ON hp.house_id = h.id WHERE ac.human_id = $1 AND (hp.perk_key = 'diplomatic_house' OR hp.perk_key = 'diplomatic_dynasty') LIMIT 1", [input.humanId]);
    const senateGavel = await tx.query("SELECT 1 FROM house_heirlooms WHERE heirloom_type = 'senate_gavel' AND equipped_by_human_id = $1 LIMIT 1", [input.humanId]);
    const houseInfluence = (diplomaticPerk.rows[0] ? 1.15 : 1) * (senateGavel.rows[0] ? 1.1 : 1);
    const weight = Math.round((1 + Math.min(2, population / 100)) * houseInfluence * 1000) / 1000;
    try {
      await tx.query('INSERT INTO ballots (proposal_id, human_id, choice, weight) VALUES ($1,$2,$3,$4)', [input.proposalId, input.humanId, input.choice, weight]);
    } catch (_error) {
      throw new Error('Ballot already recorded');
    }
    const counts = await tx.query('SELECT choice, ROUND(SUM(weight), 3) AS count FROM ballots WHERE proposal_id = $1 GROUP BY choice', [input.proposalId]);
    return { ok: true, proposalId: input.proposalId, humanId: input.humanId, vote: input.choice, weight, counts: counts.rows };
  });
}

export async function resolveProposalsInTransaction(repository: PostgresRepository, completedDay?: number): Promise<number> {
  const worldClock = await repository.query<{ genesis_at: string | null }>("SELECT genesis_at FROM world_state WHERE id = 'WORLD'");
  const now = getAuthoritativeGameTime({ genesisAt: worldClock.rows[0]?.genesis_at });
  // Resolution is an end-of-day operation. A vote remains valid throughout
  // its due day and can only be closed after that day has settled.
  const gameDay = completedDay ?? (now.gameMinute === 0 ? now.gameDay - 1 : now.gameDay);
  await repository.query("UPDATE proposals SET status = 'closed' WHERE status = 'open' AND voting_due_end_day <= $1", [gameDay]);
  // Claim each due proposal once. This protects resolution when the scheduler
  // and one or more world-snapshot requests arrive concurrently.
  const closed = await repository.query<{ id: string; institution_id: string | null; quorum: string; approval_threshold: string }>("SELECT id, institution_id, quorum, approval_threshold FROM proposals WHERE status = 'closed' AND outcome = 'pending' FOR UPDATE SKIP LOCKED");
  let resolved = 0;
  for (const proposal of closed.rows) {
    const tx = repository;
    {
      const counts = await tx.query<{ choice: string; weight: string }>('SELECT choice, COALESCE(SUM(weight), 0) AS weight FROM ballots WHERE proposal_id = $1 GROUP BY choice', [proposal.id]);
      const totals = Object.fromEntries(counts.rows.map((row) => [row.choice, Number(row.weight)]));
      const eligibleHumans = proposal.institution_id
        ? await tx.query<{ count: string }>(`SELECT COUNT(*) AS count
            FROM humans h
            JOIN memberships m ON m.human_id = h.id
            JOIN institutions i ON i.id = $1
            WHERE h.life_status = 'active'
              AND ((i.kind = 'CITY' AND m.city_id = $1)
                OR (i.kind = 'CORPORATION' AND m.corporation_id = $1))`, [proposal.institution_id])
        : await tx.query<{ count: string }>("SELECT COUNT(*) AS count FROM humans WHERE life_status = 'active'");
      const cast = (totals.support ?? 0) + (totals.oppose ?? 0) + (totals.abstain ?? 0);
      const decisive = (totals.support ?? 0) + (totals.oppose ?? 0);
      const eligibleWeight = Math.max(1, Number(eligibleHumans.rows[0]?.count ?? 0));
      const quorumMet = cast / eligibleWeight >= Number(proposal.quorum);
      const passed = quorumMet && decisive > 0 && (totals.support ?? 0) / decisive >= Number(proposal.approval_threshold);
      const outcome = !quorumMet ? 'no_quorum' : passed ? 'passed' : 'rejected';
      // Funding is not started until the first automatic execution attempt.
      // It therefore always represents seven *upcoming complete* game days.
      await tx.query(
        "UPDATE proposals SET outcome = $1, resolved_at = CURRENT_TIMESTAMP, resolved_game_day = $2, status = CASE WHEN $1 = 'passed' THEN 'approved' ELSE 'closed' END, implementation_at = CASE WHEN $1 = 'passed' THEN implementation_at ELSE NULL END, execution_status = CASE WHEN $1 = 'passed' THEN 'ready' ELSE 'not_ready' END WHERE id = $3 AND outcome = 'pending'",
        [outcome, gameDay, proposal.id],
      );
      if (passed) {
        await tx.query(
          `INSERT INTO scheduled_actions (owner_id, action_type, due_game_day, due_game_minute, due_end_game_day, priority, payload, status, correlation_id)
           SELECT institution_id, 'proposal_execution', implementation_due_end_day, 0, implementation_due_end_day, 80,
                  jsonb_build_object('proposalId', id), 'pending', 'proposal-execution:' || id
           FROM proposals WHERE id = $1
           ON CONFLICT (correlation_id) DO NOTHING`,
          [proposal.id],
        );
      }
    }
    resolved += 1;
  }
  return resolved;
}

export async function resolveProposals(repository: PostgresRepository): Promise<number> {
  return repository.transaction((tx) => resolveProposalsInTransaction(tx));
}

/**
 * Runs one automatic end-of-day execution attempt. It locks the proposal,
 * treasury and material balance together, so a successful check and spend are
 * indivisible even when other Worker requests are active.
 */
export async function executeProposal(repository: PostgresRepository, input: { proposalId: string; humanId: string; systemExecution?: boolean; completedDay?: number }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
  const proposal = await tx.query<{ id: string; institution_id: string; title: string; outcome: string; executed_at: string | null; implementation_game_day: number | null; implementation_game_minute: number | null; target_category: string | null; target_value_json: unknown; execution_status: string; challenge_status: string; created_by_human_id: string | null }>('SELECT * FROM proposals WHERE id = $1 FOR UPDATE', [input.proposalId]);
    if (!proposal.rows[0]) throw new Error('Proposal not found');
    const current = proposal.rows[0];
    if (current.outcome !== 'passed') throw new Error('Only passed proposals can be executed');
    if (current.executed_at) return { ok: true, executionStatus: current.execution_status === 'started' ? 'started' : 'executed', proposal: current };
    if (current.challenge_status === 'pending') throw new Error('Proposal is currently under constitutional challenge');
    const world = await tx.query<{ game_day: number; genesis_at: string | null }>("SELECT game_day, genesis_at FROM world_state WHERE id = 'WORLD'");
    if (!input.systemExecution) throw new Error('Proposal execution is automatic after daily settlement');
    const day = Math.max(1, Number(input.completedDay ?? world.rows[0]?.game_day ?? 1));
    const category = String(current.target_category ?? '').trim();
    const value = jsonObject(current.target_value_json);
    if (!category || !Object.keys(value).length) {
      await tx.query("UPDATE proposals SET status = 'closed', executed_at = CURRENT_TIMESTAMP, execution_status = 'skipped' WHERE id = $1", [current.id]);
      return { ok: true, executionStatus: 'skipped', reason: 'Proposal has no target rule payload', proposal: (await tx.query('SELECT * FROM proposals WHERE id = $1', [current.id])).rows[0] };
    }
    if (category === 'megaproject_procurement') {
      const bType = String(value.buildingType ?? 'geothermal-grid');
      const spec = BUILDING_CATALOG[bType] ?? BUILDING_CATALOG['geothermal-grid'];
      const cityId = current.institution_id;
      const ownershipClass = 'civic';
      const existingBuilding = await tx.query(
        "SELECT id FROM buildings WHERE city_id = $1 AND building_type = $2 AND ownership_class = $3 AND status NOT IN ('closed', 'foreclosed') LIMIT 1",
        [cityId, bType, ownershipClass],
      );
      if (existingBuilding.rows[0]) {
        await tx.query("UPDATE proposals SET status = 'closed', executed_at = CURRENT_TIMESTAMP, execution_status = 'skipped' WHERE id = $1", [current.id]);
        return { ok: true, executionStatus: 'skipped', reason: 'This building already exists for the city', proposal: (await tx.query('SELECT * FROM proposals WHERE id = $1', [current.id])).rows[0] };
      }
      const cityAccount = await tx.query<{ account_id: string; balance: string }>(
        "SELECT account_id, balance FROM account_balances WHERE account_id = $1 AND currency = 'CREDIT' FOR UPDATE",
        [`account-city-${cityId}`],
      );
      const cityMaterials = await tx.query<{ amount: string }>(
        "SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = 'material' FOR UPDATE",
        [cityId],
      );
      const requiredCredits = Number(spec.baseCreditCost ?? 0);
      const requiredMaterials = Number(spec.baseMaterialCost ?? 0);
      const capacity = await tx.query<{ total_slots: string; used_slots: string }>(
        "SELECT COALESCE((SELECT SUM(slot_footprint) FROM buildings WHERE city_id = $1 AND status NOT IN ('closed', 'foreclosed')), 0) AS used_slots, COALESCE((SELECT COUNT(*) FROM buildings WHERE city_id = $1 AND building_type = 'urban-district-module' AND status NOT IN ('closed', 'foreclosed')), 1) * 120 AS total_slots",
        [cityId],
      );
      const hasCapacity = Number(capacity.rows[0]?.total_slots ?? 0) - Number(capacity.rows[0]?.used_slots ?? 0) >= Math.max(1, Number(spec.slotFootprint ?? 2));
      const enoughCredits = Boolean(cityAccount.rows[0]) && moneyToCents(cityAccount.rows[0].balance) >= moneyToCents(requiredCredits);
      const enoughMaterials = Number(cityMaterials.rows[0]?.amount ?? 0) >= requiredMaterials;
      if (!hasCapacity || !enoughCredits || !enoughMaterials) {
        const reason = !hasCapacity ? 'Insufficient civic space' : !enoughCredits ? 'Insufficient city Credits' : 'Insufficient city Materials';
        const funding = await tx.query<{ funding_start_day: number | null; funding_due_end_day: number | null }>('SELECT funding_start_day, funding_due_end_day FROM proposals WHERE id = $1 FOR UPDATE', [current.id]);
        const startDay = Number(funding.rows[0]?.funding_start_day ?? day + 1);
        const dueDay = Number(funding.rows[0]?.funding_due_end_day ?? startDay + 6);
        const expired = day >= dueDay;
        await tx.query(
          `UPDATE proposals
           SET execution_status = $2, funding_start_day = $3, funding_due_end_day = $4,
               funding_last_checked_day = $5, funding_block_reason = $6,
               funding_requirements = jsonb_build_object(
                 'creditsRequired',$7,'creditsAvailable',$8,'materialsRequired',$9,
                 'materialsAvailable',$10,'capacityRequired',$11,'capacityAvailable',$12)
           WHERE id = $1`,
          [current.id, expired ? 'expired_unfunded' : 'awaiting_funding', startDay, dueDay, day, reason,
            requiredCredits, centsToMoney(moneyToCents(cityAccount.rows[0]?.balance ?? 0)), requiredMaterials,
            Number(cityMaterials.rows[0]?.amount ?? 0), Math.max(1, Number(spec.slotFootprint ?? 2)),
            Number(capacity.rows[0]?.total_slots ?? 0) - Number(capacity.rows[0]?.used_slots ?? 0)],
        );
        return { ok: true, executionStatus: expired ? 'expired_unfunded' : 'awaiting_funding', reason, proposal: (await tx.query('SELECT * FROM proposals WHERE id = $1', [current.id])).rows[0] };
      }
      await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: Number(world.rows[0]?.game_day ?? 0), debitAccount: cityAccount.rows[0].account_id, creditAccount: 'account-market-clearing', amount: centsToMoney(moneyToCents(requiredCredits)), reasonType: 'civic_building_procurement', reasonId: current.id, ruleVersion: 'real-estate-v2', correlationId: `CIVIC-PROCURE-${current.id}` });
      if (requiredMaterials > 0) await tx.query("UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = 'material'", [requiredMaterials, cityId]);
      const buildingId = `BLD-MUNI-${crypto.randomUUID().slice(0, 6).toUpperCase()}`;
      const catalogRes = await tx.query<{ construction_days: number }>(
        'SELECT construction_days FROM building_catalog WHERE id = $1',
        [`${bType}-t${spec.tier || 1}`],
      );
      const constructionDays = Math.max(1, Number(catalogRes.rows[0]?.construction_days ?? Math.max(2, (spec.slotFootprint ?? 2) * 2)));
      const startDay = day + 1;
      const completeDay = startDay + constructionDays - 1;

      const startMinute = (startDay - 1) * 1440;
      const completeMinute = completeDay * 1440;

      await tx.query(
        `INSERT INTO buildings (
          id, city_id, owner_id, ownership_class,
          building_type, name, tier, condition, slot_footprint,
          operating_policy, auto_repair_enabled,
          upkeep_energy, upkeep_food, upkeep_materials, upkeep_components, upkeep_compute,
          daily_operating_credits,
          resource_output_type, resource_output_amount,
          construction_started_game_day, construction_complete_game_day,
          construction_started_minute, construction_complete_minute,
          construction_start_day, construction_duration_days, construction_due_end_day, construction_progress,
          status, created_game_day
        ) VALUES ($1, $2, NULL, 'civic', $3, $4, $5, 100, $6, 'balanced', true, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, 0.0, 'under_construction', $22)`,
        [
          buildingId,
          current.institution_id,
          spec.type,
          current.title || spec.name,
          spec.tier,
          spec.slotFootprint ?? 2,
          spec.dailyEnergyUpkeep ?? 0,
          spec.dailyFoodUpkeep ?? 0,
          spec.dailyMaterialsUpkeep ?? 0,
          spec.dailyComponentsUpkeep ?? 0,
          spec.dailyComputeUpkeep ?? 0,
          spec.dailyStaffingCredits ?? 0,
          spec.resourceOutputType ?? 'credits',
          spec.resourceOutputAmount ?? 0,
          startDay,
          completeDay,
          startMinute,
          completeMinute,
          startDay,
          constructionDays,
          completeDay,
          day,
        ],
      );

      await tx.query("UPDATE proposals SET status = 'closed', executed_at = CURRENT_TIMESTAMP, executed_game_day = $2, started_at = CURRENT_TIMESTAMP, started_game_day = $2, started_action_id = $3, execution_status = 'started', funding_block_reason = NULL WHERE id = $1", [current.id, day, buildingId]);
      await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), day, 'building.construction_started', `Municipal Megaproject ${spec.name} construction started`, toNanoMarkup({ proposalId: current.id, buildingId, cityId: current.institution_id })]);
      return { ok: true, executionStatus: 'started', buildingId, proposal: (await tx.query('SELECT * FROM proposals WHERE id = $1', [current.id])).rows[0] };
    }

    if (category === 'technology' || category === 'research') {
      const buildingType = String(value.buildingType ?? value.building_type ?? '').trim();
      if (!buildingType) {
        await tx.query("UPDATE proposals SET status = 'closed', executed_at = CURRENT_TIMESTAMP, execution_status = 'skipped', funding_block_reason = 'Missing building type in research proposal' WHERE id = $1", [current.id]);
        return { ok: true, executionStatus: 'skipped', reason: 'Missing building type in research proposal', proposal: (await tx.query('SELECT * FROM proposals WHERE id = $1', [current.id])).rows[0] };
      }
      const result = await startCorporationBuildingResearchInTransaction(tx, {
        humanId: current.created_by_human_id ?? input.humanId,
        buildingType,
        correlationId: `proposal-research:${current.id}`,
      });
      await tx.query("UPDATE proposals SET status = 'closed', executed_at = CURRENT_TIMESTAMP, executed_game_day = $2, started_at = CURRENT_TIMESTAMP, started_game_day = $2, started_action_id = $3, execution_status = 'started', funding_block_reason = NULL WHERE id = $1", [current.id, day, result.project?.id ?? null]);
      return { ok: true, executionStatus: 'started', researchProject: result.project, proposal: (await tx.query('SELECT * FROM proposals WHERE id = $1', [current.id])).rows[0] };
    }

    if (!['market', 'finance', 'services', 'technology', 'megaproject_procurement'].includes(category)) throw new Error('Target rule is outside engine bounds');
    if (category === 'finance' && value.rate !== undefined && (typeof value.rate !== 'number' || Number(value.rate) < 0 || Number(value.rate) > 0.25)) throw new Error('Finance rule rate must be between 0 and 0.25');
    const quorum = value.quorum !== undefined ? Number(value.quorum) : 0.25;
    const approval = value.approvalThreshold !== undefined ? Number(value.approvalThreshold) : 0.50;
    const votingPeriod = value.votingPeriodDays !== undefined ? Number(value.votingPeriodDays) : 30;
    const activeRule = await tx.query<{ id: string; version: number }>('SELECT id, version FROM governance_rules WHERE institution_id = $1 AND category = $2 AND status = \'active\' ORDER BY version DESC LIMIT 1', [current.institution_id, category]);
    const version = Number(activeRule.rows[0]?.version ?? 0) + 1;
    const ruleId = `GOV-${current.institution_id}-${category}-v${version}`;
    await tx.query('INSERT INTO governance_rules (id, institution_id, name, category, quorum_threshold, approval_threshold, voting_period_days, version, status, created_by) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,\'active\',$9)', [ruleId, current.institution_id, current.title, category, quorum, approval, votingPeriod, version, input.humanId]);
    await tx.query("UPDATE governance_rules SET status = 'superseded' WHERE institution_id = $1 AND category = $2 AND status = 'active' AND id <> $3", [current.institution_id, category, ruleId]);
    await tx.query("UPDATE proposals SET status = 'closed', executed_at = CURRENT_TIMESTAMP, executed_game_day = $2, started_at = CURRENT_TIMESTAMP, started_game_day = $2, started_action_id = $3, execution_status = 'started', funding_block_reason = NULL WHERE id = $1", [current.id, day, ruleId]);
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), Number(world.rows[0]?.game_day ?? 0), 'rule.changed', `Rule ${category} changed`, toNanoMarkup({ proposalId: current.id, ruleId })]);
    return { ok: true, executionStatus: 'started', rule: (await tx.query('SELECT * FROM governance_rules WHERE id = $1', [ruleId])).rows[0], proposal: (await tx.query('SELECT * FROM proposals WHERE id = $1', [current.id])).rows[0] };
  });
}

/** Execute approved civic proposals and retry queued ones, expiring proposals after 7 game days. */
export async function executeQueuedProposals(repository: PostgresRepository): Promise<number> {
  const world = await repository.query<{ game_day: number; game_minute: number }>("SELECT game_day, game_minute FROM world_state WHERE id = 'WORLD'");
  const currentDay = Number(world.rows[0]?.game_day ?? 1);
  const currentMinute = Number(world.rows[0]?.game_minute ?? 0);

  // Expire queued proposals that exceeded their 7-day window
  await repository.query(
    "UPDATE proposals SET status = 'closed', execution_status = 'expired_unfunded' WHERE outcome = 'passed' AND execution_status = 'queued' AND expires_game_day IS NOT NULL AND (expires_game_day, COALESCE(expires_game_minute, 0)) < ($1::bigint, $2::integer)",
    [currentDay, currentMinute],
  );

  const queued = await repository.query<{ id: string }>(
    "SELECT p.id FROM proposals p CROSS JOIN world_state w WHERE w.id = 'WORLD' AND p.outcome = 'passed' AND p.target_category = 'megaproject_procurement' AND p.executed_at IS NULL AND p.execution_status IN ('ready', 'queued') AND (p.implementation_game_day, p.implementation_game_minute) <= (w.game_day, w.game_minute) ORDER BY p.resolved_at NULLS FIRST, p.id LIMIT 50",
  );
  let executed = 0;
  for (const proposal of queued.rows) {
    try {
      const result = await executeProposal(repository, { proposalId: proposal.id, humanId: 'SYSTEM', systemExecution: true, completedDay: currentDay });
      if (result.executionStatus === 'started' || result.executionStatus === 'skipped') executed += 1;
    } catch (error) {
      // A single unavailable city resource or capacity must not abort the world tick.
      console.warn(`[governance queue] proposal ${proposal.id} retry deferred`, error);
    }
  }
  return executed;
}

export async function challengeProposal(repository: PostgresRepository, input: { humanId: string; proposalId: string; reason: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ details: string }>("SELECT details FROM world_events WHERE event_type = 'governance.challenge_filed' AND correlation_id = $1", [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, proposalId: input.proposalId, correlationId: input.correlationId };
    const proposal = await tx.query<{ id: string; institution_id: string; outcome: string; executed_at: string | null; execution_status: string }>('SELECT id, institution_id, outcome, executed_at, execution_status FROM proposals WHERE id = $1 FOR UPDATE', [input.proposalId]);
    if (!proposal.rows[0]) throw new Error('Proposal not found');
    if (proposal.rows[0].outcome !== 'passed') throw new Error('Only passed proposals can be challenged');
    if (proposal.rows[0].executed_at) throw new Error('Proposal has already been executed');
    if (!(await eligible(tx, input.humanId, proposal.rows[0].institution_id))) throw new Error('Human is not authorized to challenge this proposal');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    await tx.query("UPDATE proposals SET challenge_status = 'pending' WHERE id = $1", [input.proposalId]);
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details, correlation_id) VALUES ($1,$2,$3,$4,$5,$6)', [crypto.randomUUID(), day, 'governance.challenge_filed', `Constitutional challenge filed for proposal ${input.proposalId}`, toNanoMarkup({ proposalId: input.proposalId, challenger: input.humanId, reason: input.reason, correlationId: input.correlationId }), input.correlationId]);
    await enqueueOutbox(tx, {
      eventKey: `governance-challenge:${input.correlationId}`,
      topic: 'world_activity',
      aggregateType: 'proposal',
      aggregateId: input.proposalId,
      payload: { type: 'world_activity', category: 'governance', action: 'constitutional_challenge_filed', proposalId: input.proposalId, gameDay: day },
    });
    return { ok: true, proposalId: input.proposalId, executionStatus: 'challenged', reason: input.reason, correlationId: input.correlationId };
  });
}

export async function resolveConstitutionalAppeal(repository: PostgresRepository, input: { humanId: string; proposalId: string; ruling: 'uphold' | 'void'; rationale: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ details: string }>("SELECT details FROM world_events WHERE event_type = 'governance.ruling_issued' AND correlation_id = $1", [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, proposalId: input.proposalId, ruling: input.ruling, correlationId: input.correlationId };
    const proposal = await tx.query<{ id: string; institution_id: string; outcome: string; executed_at: string | null; challenge_status: string }>('SELECT id, institution_id, outcome, executed_at, challenge_status FROM proposals WHERE id = $1 FOR UPDATE', [input.proposalId]);
    if (!proposal.rows[0]) throw new Error('Proposal not found');
    if (proposal.rows[0].executed_at) throw new Error('Proposal has already been executed');
    if (!(await eligible(tx, input.humanId, proposal.rows[0].institution_id))) throw new Error('Human is not authorized as a judicial delegate');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    if (input.ruling === 'void') {
      await tx.query("UPDATE proposals SET status = 'closed', outcome = 'rejected', challenge_status = 'voided', execution_status = 'skipped' WHERE id = $1", [input.proposalId]);
    } else {
      await tx.query("UPDATE proposals SET status = 'approved', challenge_status = 'upheld', execution_status = 'ready' WHERE id = $1", [input.proposalId]);
    }
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details, correlation_id) VALUES ($1,$2,$3,$4,$5,$6)', [crypto.randomUUID(), day, 'governance.ruling_issued', `Constitutional ruling for proposal ${input.proposalId}: ${input.ruling.toUpperCase()}`, toNanoMarkup({ proposalId: input.proposalId, jurist: input.humanId, ruling: input.ruling, rationale: input.rationale, correlationId: input.correlationId }), input.correlationId]);
    await enqueueOutbox(tx, {
      eventKey: `governance-ruling:${input.correlationId}`,
      topic: 'world_activity',
      aggregateType: 'proposal',
      aggregateId: input.proposalId,
      payload: { type: 'world_activity', category: 'governance', action: 'constitutional_ruling_issued', proposalId: input.proposalId, ruling: input.ruling, gameDay: day },
    });
    return { ok: true, proposalId: input.proposalId, ruling: input.ruling, executionStatus: input.ruling === 'void' ? 'voided' : 'ready', rationale: input.rationale, correlationId: input.correlationId };
  });
}
