import type { PostgresRepository } from './repository';
import { enqueueOutbox } from './outbox-postgres.ts';
import { toNanoMarkup, fromNanoMarkup } from './nano-markup.ts';
import { BUILDING_CATALOG } from './real-estate-catalog.ts';
import { transferCredits } from './financial-postgres.ts';
import { moneyToCents, centsToMoney } from './money.ts';
import { getAuthoritativeGameTime } from './game-clock.ts';
import { startCorporationBuildingResearchInTransaction } from './corporation-building-research-postgres.ts';
import { isFinancialProposalAction, proposalActionHandler, validateProposalActionSnapshot } from './proposal-actions.ts';
import { executeProposalFinancialAction } from './proposal-finance-actions.ts';
import { attemptProposalFunding } from './proposal-funding.ts';

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

function financialActionType(targetCategory: string | null | undefined): string | null {
  return ({
    approve_budget: 'APPROVE_BUDGET',
    amend_budget: 'AMEND_BUDGET',
    major_project: 'AUTHORIZE_MAJOR_PROJECT',
    authorize_grant: 'AUTHORIZE_GRANT',
    grant: 'AUTHORIZE_GRANT',
    change_tax_charter: 'CHANGE_TAX_CHARTER',
    transfer_reserve: 'TRANSFER_RESERVE',
    declare_dividend: 'DECLARE_DIVIDEND',
    approve_bailout: 'APPROVE_BAILOUT',
  } as Record<string, string>)[String(targetCategory ?? '').trim().toLowerCase()] ?? null;
}

const COMMON_GOVERNANCE_DEFAULTS = {
  quorum: 0.25,
  approvalThreshold: 0.50,
  votingPeriodDays: 3,
  implementationDelayDays: 0,
};

export function evaluateProposalVote(input: {
  voters: number;
  eligibleHumans: number;
  supportWeight: number;
  opposeWeight: number;
  quorum: number;
  approvalThreshold: number;
}): { quorumMet: boolean; passed: boolean } {
  const eligible = Math.max(1, input.eligibleHumans);
  const decisive = input.supportWeight + input.opposeWeight;
  const quorumMet = input.voters / eligible >= input.quorum;
  return {
    quorumMet,
    passed: quorumMet && decisive > 0 && input.supportWeight / decisive >= input.approvalThreshold,
  };
}

function snapshotJson(value: Record<string, unknown>): string {
  return JSON.stringify(value, Object.keys(value).sort());
}

async function snapshotHash(governance: Record<string, unknown>, action: Record<string, unknown>): Promise<string> {
  const bytes = new TextEncoder().encode(`${snapshotJson(governance)}\n${snapshotJson(action)}`);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
}

export async function createProposal(repository: PostgresRepository, input: { humanId: string; institutionId: string; title: string; body: string; expectedGovernanceRuleVersionId?: string; targetCategory: string | null; targetValue: Record<string, unknown> | null; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query('SELECT * FROM proposals WHERE institution_id = $1 AND correlation_id = $2', [input.institutionId, input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, proposal: prior.rows[0], correlationId: input.correlationId };
    if (input.targetCategory === 'megaproject_procurement' && input.targetValue?.buildingType) {
      await tx.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`${input.institutionId}:megaproject_procurement:${String(input.targetValue.buildingType)}`]);
      const existing = await tx.query<{ id: string; title: string; status: string; outcome: string | null; execution_status: string | null; target_value_json: unknown }>(
        "SELECT id, title, status, outcome, execution_status, target_value_json FROM proposals WHERE institution_id = $1 AND target_category = 'megaproject_procurement' AND executed_at IS NULL AND (decision_status IN ('scheduled', 'voting', 'passed') OR execution_status IN ('ready', 'awaiting_funding')) ORDER BY updated_at DESC",
        [input.institutionId],
      );
      const duplicate = existing.rows.find((proposal) => jsonObject(proposal.target_value_json).buildingType === input.targetValue?.buildingType);
      if (duplicate) throw new Error('A civic proposal for this building is already active or pending. No duplicate proposal was created.');

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
    const limits = await tx.query<{ max_creator: number; max_institution: number; cooldown_minutes: number }>('SELECT max_active_proposals_per_creator AS max_creator, max_active_proposals_per_institution AS max_institution, proposal_creation_cooldown_minutes AS cooldown_minutes FROM institutions WHERE id = $1', [input.institutionId]);
    const policy = limits.rows[0] ?? { max_creator: 5, max_institution: 50, cooldown_minutes: 0 };
    const activeLimits = await tx.query<{ creator_count: string; institution_count: string }>(
      `SELECT COUNT(*) FILTER (WHERE created_by_human_id = $2) AS creator_count, COUNT(*) AS institution_count
         FROM proposals WHERE institution_id = $1 AND decision_status IN ('scheduled','voting','passed')`,
      [input.institutionId, input.humanId],
    );
    if (Number(activeLimits.rows[0]?.creator_count ?? 0) >= Number(policy.max_creator)) throw new Error('Proposal creator limit reached');
    if (Number(activeLimits.rows[0]?.institution_count ?? 0) >= Number(policy.max_institution)) throw new Error('Institution proposal limit reached');
    if (Number(policy.cooldown_minutes) > 0) {
      const recent = await tx.query<{ count: string }>('SELECT COUNT(*) AS count FROM proposals WHERE institution_id = $1 AND created_by_human_id = $2 AND created_at > CURRENT_TIMESTAMP - ($3 * INTERVAL \'1 minute\')', [input.institutionId, input.humanId, Number(policy.cooldown_minutes)]);
      if (Number(recent.rows[0]?.count ?? 0) > 0) throw new Error('Proposal creation cooldown is active');
    }
    const rule = await tx.query<{ id: string; value_json: unknown; quorum_threshold: string | null; approval_threshold: string | null; voting_period_days: number | null; implementation_delay_days: number | null }>("SELECT id, value_json, quorum_threshold, approval_threshold, voting_period_days, implementation_delay_days FROM governance_rules WHERE institution_id = $1 AND category = 'governance' AND status = 'active' ORDER BY version DESC LIMIT 1", [input.institutionId]);
    let ruleRow = rule.rows[0];
    if (ruleRow && input.expectedGovernanceRuleVersionId && ruleRow.id !== input.expectedGovernanceRuleVersionId) {
      throw new Error('Governance rule version changed; refresh and retry');
    }
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
      const inserted = await tx.query<{ id: string; value_json: unknown; quorum_threshold: string | null; approval_threshold: string | null; voting_period_days: number | null; implementation_delay_days: number | null }>(
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
    const challengePeriodDays = Number(jsonObject(ruleRow.value_json).challengePeriodDays ?? 1);
    const implementationDueEndDay = votingDueEndDay + implementationDelay + challengePeriodDays;
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
          `SELECT id FROM corporation_research_projects
           WHERE target_type = 'BUILDING_BLUEPRINT' AND (id = $1 OR target_id = $1)
           ORDER BY created_at DESC LIMIT 1`,
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

    const baseTargetRule = input.targetCategory
      ? await tx.query<{ id: string }>("SELECT id FROM governance_rules WHERE institution_id = $1 AND category = $2 AND status = 'active' ORDER BY version DESC LIMIT 1", [input.institutionId, input.targetCategory])
      : { rows: [] as { id: string }[] };
    const governanceSnapshot = {
      ruleVersionId: ruleRow.id,
      quorum,
      approvalThreshold,
      votingPeriodDays,
      implementationDelayDays: implementationDelay,
      challengePeriodDays,
      fundingWindowDays: Number(input.targetValue?.fundingWindowDays ?? 7),
    };
    const catalog = buildingCatalogId
      ? (await tx.query<any>(`SELECT id, building_type, name, tier, ownership_class, slot_footprint,
          cost_credits, cost_materials, cost_energy, cost_food, cost_components, cost_compute,
          construction_days, output_credits, output_energy, output_food, output_materials,
          output_components, output_compute, upkeep_energy, upkeep_food, upkeep_materials,
          upkeep_components, upkeep_compute, operating_credits
        FROM building_catalog WHERE id = $1`, [buildingCatalogId])).rows[0]
      : null;
    const fallback = buildingCatalogId ? BUILDING_CATALOG[String(input.targetValue?.buildingType ?? input.targetValue?.type ?? '')] : null;
    const actionSnapshot: Record<string, unknown> = catalog ? {
      actionType: 'construct_civic_building',
      buildingCatalogId,
      buildingType: catalog.building_type,
      tier: Number(catalog.tier),
      creditCostUnits: moneyToCents(catalog.cost_credits ?? 0).toString(),
      materialCostUnits: BigInt(Math.round(Number(catalog.cost_materials ?? 0) * 1_000_000)).toString(),
      slotFootprint: Number(catalog.slot_footprint),
      constructionDurationDays: Number(catalog.construction_days ?? 1),
      ownershipClass: catalog.ownership_class,
      dailyEnergyUpkeep: Number(catalog.upkeep_energy ?? 0),
      dailyFoodUpkeep: Number(catalog.upkeep_food ?? 0),
      dailyMaterialsUpkeep: Number(catalog.upkeep_materials ?? 0),
      dailyComponentsUpkeep: Number(catalog.upkeep_components ?? 0),
      dailyComputeUpkeep: Number(catalog.upkeep_compute ?? 0),
      dailyStaffingCredits: Number(catalog.operating_credits ?? 0),
      resourceOutputType: catalog.output_credits > 0 ? 'credits' : catalog.output_energy > 0 ? 'energy' : catalog.output_food > 0 ? 'food' : catalog.output_materials > 0 ? 'material' : catalog.output_components > 0 ? 'components' : 'compute',
      resourceOutputAmount: Number(catalog.output_credits || catalog.output_energy || catalog.output_food || catalog.output_materials || catalog.output_components || catalog.output_compute || 0),
    } : fallback ? {
      actionType: 'construct_civic_building',
      buildingCatalogId,
      buildingType: fallback.type,
      tier: fallback.tier,
      creditCostUnits: moneyToCents(fallback.baseCreditCost).toString(),
      materialCostUnits: BigInt(Math.round(fallback.baseMaterialCost * 1_000_000)).toString(),
      slotFootprint: fallback.slotFootprint,
      constructionDurationDays: Math.max(2, fallback.slotFootprint * 2),
      ownershipClass: fallback.defaultOwnershipClass,
      dailyEnergyUpkeep: fallback.dailyEnergyUpkeep,
      dailyFoodUpkeep: fallback.dailyFoodUpkeep,
      dailyMaterialsUpkeep: fallback.dailyMaterialsUpkeep,
      dailyComponentsUpkeep: fallback.dailyComponentsUpkeep,
      dailyComputeUpkeep: fallback.dailyComputeUpkeep,
      dailyStaffingCredits: fallback.dailyStaffingCredits,
      resourceOutputType: fallback.resourceOutputType,
      resourceOutputAmount: fallback.resourceOutputAmount,
    } : {
      actionType: financialActionType(input.targetCategory) ?? (input.targetCategory === 'technology' || input.targetCategory === 'research' ? 'start_research' : input.targetCategory ? 'amend_rule' : 'generic'),
      ...(input.targetValue ?? {}),
      researchProjectId,
      buildingType: input.targetValue?.buildingType ?? input.targetValue?.building_type,
      targetCategory: input.targetCategory,
      baseRuleVersionId: baseTargetRule.rows[0]?.id ?? null,
      targetValue: input.targetValue ?? {},
      rulesVersion: baseTargetRule.rows[0]?.rules_version ?? baseTargetRule.rows[0]?.id ?? 'proposal-finance-v1',
    };
    const contractHash = await snapshotHash(governanceSnapshot, actionSnapshot);
    const actionHandler = validateProposalActionSnapshot(actionSnapshot);
    const conflictKey = input.targetCategory === 'megaproject_procurement' && input.targetValue?.buildingType
      ? `building:${input.institutionId}:${String(input.targetValue.buildingType)}`
      : null;

    await tx.query(
      `INSERT INTO proposals (
        id, institution_id, title, body, status, decision_status, opens_at, opens_game_day,
        opens_game_minute, closes_at,
        closes_game_day, closes_game_minute, rule_version_id, quorum,
        approval_threshold, implementation_delay_days, implementation_at,
        implementation_game_day, implementation_game_minute,
        target_category, target_value_json, target_kind, building_catalog_id,
        research_project_id, correlation_id, created_by_human_id,
        governance_snapshot, action_snapshot, proposal_schema_version, action_handler_version, snapshot_hash,
        submitted_game_day, voting_start_day, voting_duration_days, voting_due_end_day, implementation_due_end_day, conflict_key
      ) VALUES ($1,$2,$3,$4,'scheduled','scheduled',CURRENT_TIMESTAMP,$5,0,CURRENT_TIMESTAMP,$6,0,$7,$8,$9,$10,CURRENT_TIMESTAMP,$11,0,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25,$26,$27,$28,$29)`,
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
        JSON.stringify(governanceSnapshot),
        JSON.stringify(actionSnapshot),
        1,
        1,
        contractHash,
        currentGameDay,
        votingStartDay,
        votingPeriodDays,
        votingDueEndDay,
        implementationDueEndDay,
        conflictKey,
      ],
    );
    await tx.query(
      `INSERT INTO proposal_actions
        (id, proposal_id, sequence, action_type, handler_version, payload_snapshot, execution_status, correlation_id)
       VALUES ($1, $2, 1, $3, $4, $5, 'pending', $6)
       ON CONFLICT (correlation_id) DO NOTHING`,
      [`PA-${proposalId}-1`, proposalId, actionHandler.actionType, actionHandler.version, JSON.stringify(actionSnapshot), `proposal-action:${proposalId}:1`],
    );
    const requirementSource = await tx.query<{ economic_id: string }>('SELECT economic_id::TEXT FROM owner_registry WHERE source_id = $1 LIMIT 1', [input.institutionId]);
    const requirements = [
      { assetId: 1, units: actionSnapshot.creditCostUnits, accountType: 3 },
      { assetId: 2, units: actionSnapshot.materialCostUnits, accountType: 2 },
    ].filter((requirement) => requirement.units && BigInt(String(requirement.units)) > 0n);
    for (const requirement of requirements) {
      if (requirementSource.rows[0]?.economic_id) await tx.query(
        `INSERT INTO proposal_action_requirements (id, proposal_action_id, asset_id, required_units, source_owner_economic_id, source_account_type, requirement_kind)
         VALUES ($1,$2,$3,$4,$5,$6,'funding') ON CONFLICT (proposal_action_id, asset_id) DO NOTHING`,
        [`PAR-${proposalId}-${requirement.assetId}`, `PA-${proposalId}-1`, requirement.assetId, String(requirement.units), requirementSource.rows[0].economic_id, requirement.accountType],
      );
    }
    return { ok: true, proposal: (await tx.query('SELECT p.*, h.display_name AS creator_name FROM proposals p LEFT JOIN humans h ON h.id = p.created_by_human_id WHERE p.id = $1', [proposalId])).rows[0], createdBy: input.humanId, correlationId: input.correlationId };
  });
}

export async function castVote(repository: PostgresRepository, input: { proposalId: string; humanId: string; choice: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const proposal = await tx.query<{ institution_id: string; voting_due_end_day: number; eligibility_cutoff_game_day: number }>("SELECT institution_id, voting_due_end_day, eligibility_cutoff_game_day FROM proposals WHERE id = $1 AND decision_status = 'voting'", [input.proposalId]);
    if (!proposal.rows[0]) throw new Error('Open proposal not found');
    const world = await tx.query<{ genesis_at: string | null }>("SELECT genesis_at FROM world_state WHERE id = 'WORLD'");
    const now = getAuthoritativeGameTime({ genesisAt: world.rows[0]?.genesis_at });
    if (now.gameDay > Number(proposal.rows[0].voting_due_end_day)) throw new Error('Voting deadline has passed');
    if (!(await eligible(tx, input.humanId, proposal.rows[0].institution_id))) throw new Error('Human is not eligible to vote at this institution');
    const cutoff = Number(proposal.rows[0].eligibility_cutoff_game_day ?? 0);
    const eligibleAtStart = await tx.query(
      `SELECT 1 FROM humans h
       JOIN memberships m ON m.human_id = h.id
       JOIN institutions i ON i.id = $1
       WHERE h.id = $2 AND h.life_status = 'active' AND m.joined_game_day <= $3
         AND ((i.kind = 'CITY' AND m.city_id = $1)
           OR (i.kind = 'CORPORATION' AND m.corporation_id = $1))
       LIMIT 1`,
      [proposal.rows[0].institution_id, input.humanId, cutoff],
    );
    if (!eligibleAtStart.rows[0]) throw new Error('Human was not eligible when voting started');
    const representation = await tx.query<{ member_count: string | null; residents: string | null }>('SELECT corporations.member_count, cities.residents FROM memberships LEFT JOIN corporations ON corporations.id = memberships.corporation_id LEFT JOIN cities ON cities.id = memberships.city_id WHERE memberships.human_id = $1 LIMIT 1', [input.humanId]);
    const population = Number(representation.rows[0]?.member_count ?? representation.rows[0]?.residents ?? 0);
    const diplomaticPerk = await tx.query("SELECT 1 FROM humans hu JOIN houses h ON h.id = hu.house_id JOIN house_perks hp ON hp.house_id = h.id WHERE hu.id = $1 AND (hp.perk_key = 'diplomatic_house' OR hp.perk_key = 'diplomatic_dynasty') LIMIT 1", [input.humanId]);
    const senateGavel = await tx.query("SELECT 1 FROM house_heirlooms WHERE heirloom_type = 'senate_gavel' AND equipped_by_human_id = $1 LIMIT 1", [input.humanId]);
    const houseInfluence = (diplomaticPerk.rows[0] ? 1.15 : 1) * (senateGavel.rows[0] ? 1.1 : 1);
    const weight = Math.round((1 + Math.min(2, population / 100)) * houseInfluence * 1000) / 1000;
    try {
      const ballot = await tx.query(
        `INSERT INTO ballots (proposal_id, house_id, human_id, choice, weight)
         SELECT $1, h.house_id, h.id, $3, $4
         FROM humans h
         WHERE h.id = $2
         ON CONFLICT (proposal_id, house_id) DO NOTHING`,
        [input.proposalId, input.humanId, input.choice, weight],
      );
      if (ballot.rowCount !== 1) throw new Error('Ballot already recorded');
      await tx.query(
        `INSERT INTO proposal_vote_totals (
           proposal_id, voter_count, support_count, oppose_count, abstain_count,
           support_weight, oppose_weight, abstain_weight, updated_at
         ) VALUES ($1, 1, $2, $3, $4, $5, $6, $7, CURRENT_TIMESTAMP)
         ON CONFLICT (proposal_id) DO UPDATE SET
           voter_count = proposal_vote_totals.voter_count + 1,
           support_count = proposal_vote_totals.support_count + EXCLUDED.support_count,
           oppose_count = proposal_vote_totals.oppose_count + EXCLUDED.oppose_count,
           abstain_count = proposal_vote_totals.abstain_count + EXCLUDED.abstain_count,
           support_weight = proposal_vote_totals.support_weight + EXCLUDED.support_weight,
           oppose_weight = proposal_vote_totals.oppose_weight + EXCLUDED.oppose_weight,
           abstain_weight = proposal_vote_totals.abstain_weight + EXCLUDED.abstain_weight,
           updated_at = CURRENT_TIMESTAMP`,
        [input.proposalId, input.choice === 'support' ? 1 : 0, input.choice === 'oppose' ? 1 : 0, input.choice === 'abstain' ? 1 : 0, input.choice === 'support' ? weight : 0, input.choice === 'oppose' ? weight : 0, input.choice === 'abstain' ? weight : 0],
      );
    } catch (_error) {
      throw new Error('Ballot already recorded');
    }
    const counts = await tx.query('SELECT * FROM proposal_vote_totals WHERE proposal_id = $1', [input.proposalId]);
    return { ok: true, proposalId: input.proposalId, humanId: input.humanId, vote: input.choice, weight, counts: counts.rows };
  });
}

export async function resolveProposalsInTransaction(repository: PostgresRepository, completedDay?: number): Promise<number> {
  const worldClock = await repository.query<{ genesis_at: string | null }>("SELECT genesis_at FROM world_state WHERE id = 'WORLD'");
  const now = getAuthoritativeGameTime({ genesisAt: worldClock.rows[0]?.genesis_at });
  // Resolution is an end-of-day operation. A vote remains valid throughout
  // its due day and can only be closed after that day has settled.
  const gameDay = completedDay ?? (now.gameMinute === 0 ? now.gameDay - 1 : now.gameDay);
  await repository.query("UPDATE proposals SET status = 'closed' WHERE decision_status = 'voting' AND voting_due_end_day <= $1", [gameDay]);
  // Claim each due proposal once. This protects resolution when the scheduler
  // and one or more world-snapshot requests arrive concurrently.
  const closed = await repository.query<{ id: string; institution_id: string | null; quorum: string; approval_threshold: string; eligible_voter_count: string | null }>("SELECT id, institution_id, quorum, approval_threshold, eligible_voter_count FROM proposals WHERE decision_status = 'voting' AND voting_due_end_day <= $1 AND outcome = 'pending' FOR UPDATE SKIP LOCKED", [gameDay]);
  let resolved = 0;
  for (const proposal of closed.rows) {
    const tx = repository;
    {
      const counts = await tx.query<{ support_weight: string; oppose_weight: string; abstain_weight: string; voter_count: string }>('SELECT support_weight, oppose_weight, abstain_weight, voter_count FROM proposal_vote_totals WHERE proposal_id = $1', [proposal.id]);
      const totals = counts.rows[0] ?? { support_weight: '0', oppose_weight: '0', abstain_weight: '0', voter_count: '0' };
      const eligibleHumans = proposal.institution_id
        ? await tx.query<{ count: string }>(`SELECT COUNT(*) AS count
            FROM humans h
            JOIN memberships m ON m.human_id = h.id
            JOIN institutions i ON i.id = $1
            WHERE h.life_status = 'active'
              AND ((i.kind = 'CITY' AND m.city_id = $1)
                OR (i.kind = 'CORPORATION' AND m.corporation_id = $1))`, [proposal.institution_id])
        : await tx.query<{ count: string }>("SELECT COUNT(*) AS count FROM humans WHERE life_status = 'active'");
      const voteResult = evaluateProposalVote({
        voters: Number(totals.voter_count ?? 0),
        eligibleHumans: Number(proposal.eligible_voter_count ?? eligibleHumans.rows[0]?.count ?? 0),
        supportWeight: Number(totals.support_weight ?? 0),
        opposeWeight: Number(totals.oppose_weight ?? 0),
        quorum: Number(proposal.quorum),
        approvalThreshold: Number(proposal.approval_threshold),
      });
      const { quorumMet, passed } = voteResult;
      const outcome = !quorumMet ? 'no_quorum' : passed ? 'passed' : 'rejected';
      // Funding is not started until the first automatic execution attempt.
      // It therefore always represents seven *upcoming complete* game days.
      await tx.query(
        "UPDATE proposals SET outcome = $1, decision_status = $1, resolved_at = CURRENT_TIMESTAMP, resolved_game_day = $2, status = CASE WHEN $1 = 'passed' THEN 'approved' ELSE 'closed' END, implementation_at = CASE WHEN $1 = 'passed' THEN implementation_at ELSE NULL END, execution_status = CASE WHEN $1 = 'passed' THEN 'ready' ELSE 'not_ready' END WHERE id = $3 AND outcome = 'pending'",
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
  const proposal = await tx.query<{ id: string; institution_id: string; title: string; decision_status: string; outcome: string; executed_at: string | null; implementation_game_day: number | null; implementation_game_minute: number | null; target_category: string | null; target_value_json: unknown; action_snapshot: unknown; governance_snapshot: unknown; execution_status: string; challenge_status: string; created_by_human_id: string | null }>('SELECT * FROM proposals WHERE id = $1 FOR UPDATE', [input.proposalId]);
    if (!proposal.rows[0]) throw new Error('Proposal not found');
    const current = proposal.rows[0];
    if (current.decision_status !== 'passed' && current.outcome !== 'passed') throw new Error('Only passed proposals can be executed');
    if (current.executed_at) return { ok: true, executionStatus: current.execution_status === 'started' ? 'started' : 'executed', proposal: current };
    if (current.challenge_status === 'pending') throw new Error('Proposal is currently under constitutional challenge');
    const world = await tx.query<{ game_day: number; genesis_at: string | null }>("SELECT game_day, genesis_at FROM world_state WHERE id = 'WORLD'");
    if (!input.systemExecution) throw new Error('Proposal execution is automatic after daily settlement');
    const day = Math.max(1, Number(input.completedDay ?? world.rows[0]?.game_day ?? 1));
    const category = String(current.target_category ?? '').trim();
    const value = jsonObject(current.target_value_json);
    const action = jsonObject(current.action_snapshot);
    const actionHandler = proposalActionHandler(action.actionType);
    await actionHandler.validateExecution({ repository: tx, proposal: current as Record<string, unknown>, action, gameDay: day });
    if (isFinancialProposalAction(action.actionType)) {
      const result = await executeProposalFinancialAction(tx, current as Record<string, unknown>, action, day);
      await tx.query("UPDATE proposals SET status = 'closed', executed_at = CURRENT_TIMESTAMP, execution_status = 'completed' WHERE id = $1", [current.id]);
      await tx.query("UPDATE proposal_actions SET execution_status = 'completed', completed_game_day = $2, result_json = $3 WHERE proposal_id = $1 AND sequence = 1", [current.id, day, JSON.stringify(result)]);
      return { ok: true, executionStatus: 'completed', result, proposal: (await tx.query('SELECT * FROM proposals WHERE id = $1', [current.id])).rows[0] };
    }
    await tx.query(
      `UPDATE proposal_actions
       SET execution_status = 'running', started_game_day = $2
       WHERE proposal_id = $1 AND sequence = 1 AND execution_status IN ('pending', 'awaiting_resources')`,
      [current.id, day],
    );
    const finishAction = async (status: string, result: Record<string, unknown> = {}) => {
      await tx.query(
        `UPDATE proposal_actions
         SET execution_status = $2, completed_game_day = CASE WHEN $2 = 'completed' THEN $3 ELSE completed_game_day END, result_json = $4
         WHERE proposal_id = $1 AND sequence = 1`,
        [current.id, status, day, JSON.stringify(result)],
      );
    };
    const fundingAttempt = await attemptProposalFunding(tx, current.id, day);
    if (fundingAttempt.configured && !fundingAttempt.available) {
      const funding = await tx.query<{ funding_start_day: number | null; funding_due_end_day: number | null }>('SELECT funding_start_day, funding_due_end_day FROM proposals WHERE id = $1 FOR UPDATE', [current.id]);
      const startDay = Number(funding.rows[0]?.funding_start_day ?? day + 1);
      const dueDay = Number(funding.rows[0]?.funding_due_end_day ?? startDay + 6);
      const expired = day >= dueDay;
      await tx.query('UPDATE proposals SET execution_status = $2, funding_start_day = $3, funding_due_end_day = $4, funding_last_checked_day = $5, funding_block_reason = $6 WHERE id = $1', [current.id, expired ? 'expired_unfunded' : 'awaiting_funding', startDay, dueDay, day, fundingAttempt.reason]);
      await finishAction(expired ? 'expired' : 'awaiting_resources', { reason: fundingAttempt.reason });
      return { ok: true, executionStatus: expired ? 'expired_unfunded' : 'awaiting_funding', reason: fundingAttempt.reason, proposal: (await tx.query('SELECT * FROM proposals WHERE id = $1', [current.id])).rows[0] };
    }
    const v2FundingPosted = fundingAttempt.configured;
    if (!category || !Object.keys(value).length) {
      await tx.query("UPDATE proposals SET status = 'closed', executed_at = CURRENT_TIMESTAMP, execution_status = 'skipped' WHERE id = $1", [current.id]);
      await finishAction('completed', { executionStatus: 'skipped' });
      return { ok: true, executionStatus: 'skipped', reason: 'Proposal has no target rule payload', proposal: (await tx.query('SELECT * FROM proposals WHERE id = $1', [current.id])).rows[0] };
    }
    if (category === 'megaproject_procurement') {
      if (action.actionType !== 'construct_civic_building' || !action.buildingType) {
        throw new Error('Proposal contract is missing its immutable building action snapshot');
      }
      const bType = String(action.buildingType);
      const spec = {
        type: bType,
        name: String(action.name ?? current.title),
        tier: Number(action.tier ?? 1),
        slotFootprint: Number(action.slotFootprint ?? 1),
        baseCreditCost: Number(BigInt(String(action.creditCostUnits ?? '0'))) / 100,
        baseMaterialCost: Number(BigInt(String(action.materialCostUnits ?? '0'))) / 1_000_000,
        constructionDays: Number(action.constructionDurationDays ?? 1),
        defaultOwnershipClass: String(action.ownershipClass ?? 'civic'),
        dailyEnergyUpkeep: Number(action.dailyEnergyUpkeep ?? 0),
        dailyFoodUpkeep: Number(action.dailyFoodUpkeep ?? 0),
        dailyMaterialsUpkeep: Number(action.dailyMaterialsUpkeep ?? 0),
        dailyComponentsUpkeep: Number(action.dailyComponentsUpkeep ?? 0),
        dailyComputeUpkeep: Number(action.dailyComputeUpkeep ?? 0),
        dailyStaffingCredits: Number(action.dailyStaffingCredits ?? 0),
        resourceOutputType: String(action.resourceOutputType ?? 'credits'),
        resourceOutputAmount: Number(action.resourceOutputAmount ?? 0),
      };
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
      const requiredCredits = spec.baseCreditCost;
      const requiredMaterials = spec.baseMaterialCost;
      const capacity = await tx.query<{ total_slots: string; used_slots: string }>(
        "SELECT COALESCE((SELECT SUM(slot_footprint) FROM buildings WHERE city_id = $1 AND status NOT IN ('closed', 'foreclosed')), 0) AS used_slots, COALESCE((SELECT COUNT(*) FROM buildings WHERE city_id = $1 AND building_type = 'urban-district-module' AND status NOT IN ('closed', 'foreclosed')), 1) * 120 AS total_slots",
        [cityId],
      );
      const hasCapacity = Number(capacity.rows[0]?.total_slots ?? 0) - Number(capacity.rows[0]?.used_slots ?? 0) >= Math.max(1, Number(spec.slotFootprint ?? 2));
      const enoughCredits = v2FundingPosted || (Boolean(cityAccount.rows[0]) && moneyToCents(cityAccount.rows[0].balance) >= moneyToCents(requiredCredits));
      const enoughMaterials = v2FundingPosted || Number(cityMaterials.rows[0]?.amount ?? 0) >= requiredMaterials;
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
        await finishAction(expired ? 'expired' : 'awaiting_resources', { reason });
        return { ok: true, executionStatus: expired ? 'expired_unfunded' : 'awaiting_funding', reason, proposal: (await tx.query('SELECT * FROM proposals WHERE id = $1', [current.id])).rows[0] };
      }
      if (!v2FundingPosted) {
        await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: Number(world.rows[0]?.game_day ?? 0), debitAccount: cityAccount.rows[0].account_id, creditAccount: 'account-market-clearing', amount: centsToMoney(moneyToCents(requiredCredits)), reasonType: 'civic_building_procurement', reasonId: current.id, ruleVersion: 'real-estate-v2', correlationId: `CIVIC-PROCURE-${current.id}` });
        if (requiredMaterials > 0) await tx.query("UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = 'material'", [requiredMaterials, cityId]);
      }
      const buildingId = `BLD-MUNI-${crypto.randomUUID().slice(0, 6).toUpperCase()}`;
      const constructionDays = Math.max(1, spec.constructionDays);
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
          spec.dailyEnergyUpkeep,
          spec.dailyFoodUpkeep,
          spec.dailyMaterialsUpkeep,
          spec.dailyComponentsUpkeep,
          spec.dailyComputeUpkeep,
          spec.dailyStaffingCredits,
          spec.resourceOutputType,
          spec.resourceOutputAmount,
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
      await finishAction('completed', { executionStatus: 'started', buildingId });
      await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), day, 'building.construction_started', `Municipal Megaproject ${spec.name} construction started`, toNanoMarkup({ proposalId: current.id, buildingId, cityId: current.institution_id })]);
      return { ok: true, executionStatus: 'started', buildingId, proposal: (await tx.query('SELECT * FROM proposals WHERE id = $1', [current.id])).rows[0] };
    }

    if (category === 'technology' || category === 'research') {
      const buildingType = String(value.buildingType ?? value.building_type ?? '').trim();
      if (!buildingType) {
        await tx.query("UPDATE proposals SET status = 'closed', executed_at = CURRENT_TIMESTAMP, execution_status = 'skipped', funding_block_reason = 'Missing building type in research proposal' WHERE id = $1", [current.id]);
        await finishAction('completed', { executionStatus: 'skipped' });
        return { ok: true, executionStatus: 'skipped', reason: 'Missing building type in research proposal', proposal: (await tx.query('SELECT * FROM proposals WHERE id = $1', [current.id])).rows[0] };
      }
      const result = await startCorporationBuildingResearchInTransaction(tx, {
        humanId: current.created_by_human_id ?? input.humanId,
        buildingType,
        correlationId: `proposal-research:${current.id}`,
      });
      await tx.query("UPDATE proposals SET status = 'closed', executed_at = CURRENT_TIMESTAMP, executed_game_day = $2, started_at = CURRENT_TIMESTAMP, started_game_day = $2, started_action_id = $3, execution_status = 'started', funding_block_reason = NULL WHERE id = $1", [current.id, day, result.project?.id ?? null]);
      await finishAction('completed', { executionStatus: 'started', researchProjectId: result.project?.id ?? null });
      return { ok: true, executionStatus: 'started', researchProject: result.project, proposal: (await tx.query('SELECT * FROM proposals WHERE id = $1', [current.id])).rows[0] };
    }

    if (!['market', 'finance', 'services', 'technology', 'megaproject_procurement'].includes(category)) throw new Error('Target rule is outside engine bounds');
    if (category === 'finance' && value.rate !== undefined && (typeof value.rate !== 'number' || Number(value.rate) < 0 || Number(value.rate) > 0.25)) throw new Error('Finance rule rate must be between 0 and 0.25');
    const quorum = value.quorum !== undefined ? Number(value.quorum) : 0.25;
    const approval = value.approvalThreshold !== undefined ? Number(value.approvalThreshold) : 0.50;
    const votingPeriod = value.votingPeriodDays !== undefined ? Number(value.votingPeriodDays) : 30;
    const activeRule = await tx.query<{ id: string; version: number }>('SELECT id, version FROM governance_rules WHERE institution_id = $1 AND category = $2 AND status = \'active\' ORDER BY version DESC LIMIT 1', [current.institution_id, category]);
    const baseRuleVersionId = action.baseRuleVersionId ? String(action.baseRuleVersionId) : null;
    if (baseRuleVersionId !== (activeRule.rows[0]?.id ?? null)) {
      await tx.query("UPDATE proposals SET execution_status = 'stale_conflict', funding_block_reason = 'Target rule changed before execution' WHERE id = $1", [current.id]);
      await finishAction('stale_conflict', { baseRuleVersionId, currentRuleVersionId: activeRule.rows[0]?.id ?? null });
      return { ok: true, executionStatus: 'stale_conflict', reason: 'Target rule changed before execution', proposal: (await tx.query('SELECT * FROM proposals WHERE id = $1', [current.id])).rows[0] };
    }
    const version = Number(activeRule.rows[0]?.version ?? 0) + 1;
    const ruleId = `GOV-${current.institution_id}-${category}-v${version}`;
    await tx.query("UPDATE governance_rules SET status = 'superseded' WHERE institution_id = $1 AND category = $2 AND status = 'active' AND id <> $3", [current.institution_id, category, ruleId]);
    await tx.query('UPDATE governance_rules SET effective_to_game_day = $3 WHERE institution_id = $1 AND category = $2 AND status = \'superseded\' AND effective_to_game_day IS NULL', [current.institution_id, category, day]);
    await tx.query('INSERT INTO governance_rules (id, institution_id, name, category, quorum_threshold, approval_threshold, voting_period_days, version, status, created_by, effective_from_game_day, effective_to_game_day) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,\'active\',$9,$10,NULL)', [ruleId, current.institution_id, current.title, category, quorum, approval, votingPeriod, version, input.humanId, day + 1]);
    await tx.query("UPDATE proposals SET status = 'closed', executed_at = CURRENT_TIMESTAMP, executed_game_day = $2, started_at = CURRENT_TIMESTAMP, started_game_day = $2, started_action_id = $3, execution_status = 'started', funding_block_reason = NULL WHERE id = $1", [current.id, day, ruleId]);
    await finishAction('completed', { executionStatus: 'started', ruleId });
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), Number(world.rows[0]?.game_day ?? 0), 'rule.changed', `Rule ${category} changed`, toNanoMarkup({ proposalId: current.id, ruleId })]);
    return { ok: true, executionStatus: 'started', rule: (await tx.query('SELECT * FROM governance_rules WHERE id = $1', [ruleId])).rows[0], proposal: (await tx.query('SELECT * FROM proposals WHERE id = $1', [current.id])).rows[0] };
  });
}

export async function challengeProposal(repository: PostgresRepository, input: { humanId: string; proposalId: string; reason: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ details: string }>("SELECT details FROM world_events WHERE event_type = 'governance.challenge_filed' AND correlation_id = $1", [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, proposalId: input.proposalId, correlationId: input.correlationId };
    const proposal = await tx.query<{ id: string; institution_id: string; outcome: string; executed_at: string | null; execution_status: string }>('SELECT id, institution_id, outcome, executed_at, execution_status FROM proposals WHERE id = $1 FOR UPDATE', [input.proposalId]);
    if (!proposal.rows[0]) throw new Error('Proposal not found');
    if (proposal.rows[0].outcome !== 'passed') throw new Error('Only passed proposals can be challenged');
    if (proposal.rows[0].executed_at) throw new Error('Proposal has already been executed');
    const authority = await tx.query('SELECT 1 FROM proposal_challenge_authorities WHERE institution_id = $1 AND human_id = $2 AND role_code IN (\'constitutional_judge\', \'judicial_delegate\', \'ouc_court\') AND status = \'active\' LIMIT 1', [proposal.rows[0].institution_id, input.humanId]);
    if (!authority.rows[0]) throw new Error('Constitutional challenge authority is required');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    const snapshot = await tx.query<{ governance_snapshot: unknown; resolved_game_day: number | null }>('SELECT governance_snapshot, resolved_game_day FROM proposals WHERE id = $1', [input.proposalId]);
    const governance = jsonObject(snapshot.rows[0]?.governance_snapshot);
    const challengeDays = Number(governance.challengePeriodDays ?? 0);
    if (day > Number(snapshot.rows[0]?.resolved_game_day ?? day) + challengeDays) throw new Error('Constitutional challenge window has closed');
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
      await tx.query("UPDATE proposals SET status = 'closed', decision_status = 'rejected', outcome = 'rejected', challenge_status = 'voided', execution_status = 'not_ready' WHERE id = $1", [input.proposalId]);
    } else {
      await tx.query("UPDATE proposals SET status = 'approved', decision_status = 'passed', challenge_status = 'upheld', execution_status = 'ready' WHERE id = $1", [input.proposalId]);
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
