import type { PostgresRepository } from './repository.ts';
import { moneyToCents } from './money.ts';
import { createNotification } from './notifications-postgres.ts';
import { createGameEvent } from './game-events-postgres.ts';
import { toNanoMarkup } from './nano-markup.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';
import { runEconomicMutation, postEconomicTransaction } from './settlement-barrier-postgres.ts';

export type TechnologyCatalogRow = {
  id: string;
  code: string;
  name: string;
  category: string;
  description: string;
  patentable: boolean;
  patent_exclusivity_days: number;
  research_credit_cost_units: string;
  research_points_required: string;
  research_duration_game_days: string;
  status: string;
  definition_version: string;
  effective_from_game_day: number;
  effective_to_game_day: number | null;
  effects: Array<Record<string, unknown>>;
};

export function mapTechnologyCatalogRow(row: TechnologyCatalogRow): Record<string, unknown> {
  return {
    ...row,
    researchCostUnits: row.research_credit_cost_units,
    researchPointsRequired: row.research_points_required,
    researchDurationGameDays: row.research_duration_game_days,
    effects: row.effects ?? [],
    kind: 'approved_capability',
    tradeable: false,
    playerCreated: false,
  };
}

async function readTechnologyCatalog(tx: PostgresRepository, gameDay?: number): Promise<TechnologyCatalogRow[]> {
  const day = gameDay ?? 0;
  const result = await tx.query<TechnologyCatalogRow>(`SELECT DISTINCT ON (tc.code) tc.id, tc.code, tc.name, tc.category, tc.description,
      patentable, patent_exclusivity_days, credit_cost_units::TEXT AS research_credit_cost_units,
      research_points_required::TEXT, research_duration_game_days::TEXT, status, definition_version,
      effective_from_game_day, effective_to_game_day,
      (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'effectType', e.effect_type, 'modifierFamily', e.modifier_family, 'targetType', e.target_type,
        'targetKey', e.target_key, 'modifierBps', e.modifier_bps
      ) ORDER BY e.id), '[]'::JSONB) FROM technology_effects e WHERE e.technology_id = tc.id) AS effects
    FROM technology_catalog tc
    WHERE tc.effective_from_game_day <= $1
      AND (tc.effective_to_game_day IS NULL OR tc.effective_to_game_day >= $1)
      AND tc.status = 'ACTIVE'
    ORDER BY tc.code, tc.effective_from_game_day DESC, tc.definition_version DESC`, [day]);
  return result.rows;
}

export async function corporationHasTechnologyAccess(
  repository: PostgresRepository,
  input: { corporationEconomicId: number | string; technologyId: string; gameDay: number },
): Promise<boolean> {
  const result = await repository.query<{ has_access: boolean }>(
    'SELECT has_access FROM earth_resolve_corporation_technology_access($1, $2, $3)',
    [input.corporationEconomicId, input.technologyId, input.gameDay],
  );
  return Boolean(result.rows[0]?.has_access);
}

export async function resolveCorporationTechnologyAccess(
  repository: PostgresRepository,
  input: { corporationEconomicId: number | string; technologyId: string; gameDay: number },
): Promise<{ hasAccess: boolean; reason: string | null; sourceId: string | null }> {
  const result = await repository.query<{ has_access: boolean; access_reason: string; source_id: string }>(
    'SELECT * FROM earth_resolve_corporation_technology_access($1, $2, $3)',
    [input.corporationEconomicId, input.technologyId, input.gameDay],
  );
  return { hasAccess: Boolean(result.rows[0]?.has_access), reason: result.rows[0]?.access_reason ?? null, sourceId: result.rows[0]?.source_id ?? null };
}

async function requireResearchJurisdiction(tx: PostgresRepository, ownerId: string): Promise<void> {
  const membership = await tx.query<{ corporation_id: string | null }>("SELECT ha.corporation_id FROM humans h JOIN house_affiliations ha ON ha.house_id = h.house_id WHERE h.id = $1 AND ha.status = 'ACTIVE' LIMIT 1", [ownerId]);
  if (!membership.rows[0]?.corporation_id) throw new Error('Research requires active corporation membership');
}

export async function createResearchProject(repository: PostgresRepository, input: { ownerId: string; name: string; budget: number; focus: string; correlationId: string }): Promise<Record<string, unknown>> {
  return runEconomicMutation(repository, async (tx, clock) => {
    await requireResearchJurisdiction(tx, input.ownerId);
    const membership = await tx.query<{ corporation_id: string }>("SELECT ha.corporation_id FROM humans h JOIN house_affiliations ha ON ha.house_id = h.house_id WHERE h.id = $1 AND ha.status = 'ACTIVE' LIMIT 1", [input.ownerId]);
    const corporationId = membership.rows[0].corporation_id;
    const day = clock.gameDay;
    const catalog = await readTechnologyCatalog(tx, day);
    const catalogEntry = catalog.find((technology) => technology.name === input.name || technology.code === input.name);
    const minimumBudgetCents = Number(catalogEntry?.research_credit_cost_units ?? 0n) / 1;
    if (!catalogEntry || moneyToCents(input.budget) < minimumBudgetCents) {
      throw new Error(`Research funding for ${input.name} must meet the database catalog cost`);
    }
    await tx.query('SELECT earth_assert_technology_research_allowed($1, $2)', [catalogEntry.id, day + 1]);
    const prior = await tx.query<{ id: string }>(`SELECT p.id FROM corporation_research_projects p
      JOIN owner_registry o ON o.economic_id = p.corporation_economic_id
      WHERE o.id = $1 AND p.correlation_id = $2`, [corporationId, input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, project: (await tx.query('SELECT * FROM corporation_research_projects WHERE id = $1', [prior.rows[0].id])).rows[0], correlationId: input.correlationId };
    const budgetCents = moneyToCents(input.budget);
    const projectId = `PROJECT-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    const corporationOwner = await tx.query<{ economic_id: string }>('SELECT economic_id::TEXT FROM owner_registry WHERE id = $1', [corporationId]);
    if (!corporationOwner.rows[0]) throw new Error('Corporation economic owner is not provisioned');
    await tx.query('SELECT earth_assert_technology_prerequisites_met($1, $2, $3)', [corporationOwner.rows[0].economic_id, catalogEntry.id, day + 1]);
    const fundingAccounts = await tx.query<{ debit_account_id: string; research_account_id: string }>(`SELECT payer.id::TEXT AS debit_account_id, service.id::TEXT AS research_account_id
      FROM economic_accounts payer
      JOIN owner_registry payer_owner ON payer_owner.economic_id = payer.owner_economic_id AND payer_owner.id = $1
      JOIN owner_registry system_owner ON system_owner.id = 'SYSTEM'
      JOIN economic_accounts service ON service.owner_economic_id = system_owner.economic_id
        AND service.asset_id = 1 AND service.account_type = 'SYSTEM_ACCOUNT' AND service.status = 'ACTIVE'
      WHERE payer.asset_id = 1 AND payer.account_type = 'OPERATIONS'
        AND payer.status = 'ACTIVE'
      ORDER BY payer.id
      LIMIT 1`, [corporationId]);
    if (!fundingAccounts.rows[0]) throw new Error('Corporation V2 funding account or system research account is not provisioned');
    const budgetLine = (await tx.query<{ id: string }>(`SELECT l.id FROM institution_budget_lines l JOIN budget_categories c ON c.id=l.category_id
      WHERE l.institution_id=$1 AND c.institution_kind='CORPORATION' AND c.category_code='RESEARCH'
        AND l.fiscal_period_id=(SELECT id FROM fiscal_periods WHERE start_game_day <= $2 AND end_game_day >= $2 AND status='ACTIVE' LIMIT 1)
        AND l.authorized_units-l.committed_units-l.spent_units >= $3 FOR UPDATE`, [corporationId, day, budgetCents.toString()])).rows[0];
    if (!budgetLine) throw new Error('Corporation research budget authority is unavailable');
    const commitmentId = `COMMIT-RESEARCH-${projectId}`;
    await tx.query(`INSERT INTO institution_budget_commitments
      (id,institution_id,budget_line_id,source_type,source_id,original_units,remaining_units,status,due_game_day)
      VALUES ($1,$2,$3,'CORPORATION_RESEARCH',$4,$5,$5,'OPEN',$6)`, [commitmentId, corporationId, budgetLine.id, projectId, budgetCents.toString(), day + 30]);
    await tx.query('UPDATE institution_budget_lines SET committed_units=committed_units+$1 WHERE id=$2', [budgetCents.toString(), budgetLine.id]);
    const funding = await postEconomicTransaction(tx, {
      correlationId: input.correlationId,
      kind: 'RESEARCH_FUNDING',
      sourceType: 'CORPORATION_RESEARCH',
      sourceId: projectId,
      rulesVersion: `technology-catalog-v${catalogEntry.definition_version}`,
      entries: [
        { account_id: fundingAccounts.rows[0].debit_account_id, delta_units: (-BigInt(budgetCents)).toString(), asset_id: 1 },
        { account_id: fundingAccounts.rows[0].research_account_id, delta_units: BigInt(budgetCents).toString(), asset_id: 1 },
      ],
    }, clock);
    const fundingTransactionId = funding.transactionId;
    if (!fundingTransactionId) throw new Error('Research funding transaction was not created');
    await tx.query(`UPDATE institution_budget_commitments SET remaining_units=0,status='PAID' WHERE id=$1`, [commitmentId]);
    await tx.query('UPDATE institution_budget_lines SET committed_units=committed_units-$1, spent_units=spent_units+$1 WHERE id=$2', [budgetCents.toString(), budgetLine.id]);
    await tx.query(`INSERT INTO corporation_research_projects
      (id, corporation_economic_id, target_type, target_id, definition_version,
       required_research_points, progress_research_points, credit_cost_units,
       priority, status, started_game_day, funding_transaction_id, correlation_id, definition_snapshot)
      VALUES ($1,$2,'TECHNOLOGY',$3,$4,$5,0, $6,100,'ACTIVE',$7,$8,$9,$10::jsonb)`,
      [projectId, corporationOwner.rows[0].economic_id, catalogEntry.id, `technology-catalog-v${catalogEntry.definition_version}`, catalogEntry.research_points_required, catalogEntry.research_credit_cost_units, day, fundingTransactionId, input.correlationId, toNanoMarkup({ technologyId: catalogEntry.id, code: catalogEntry.code, name: catalogEntry.name, definitionVersion: catalogEntry.definition_version, researchCreditCostUnits: catalogEntry.research_credit_cost_units, researchPointsRequired: catalogEntry.research_points_required, effects: catalogEntry.effects, patentable: catalogEntry.patentable, patentExclusivityDays: catalogEntry.patent_exclusivity_days })]);
    const senderHouse = await tx.query<{ house_id: string }>('SELECT house_id FROM humans WHERE id = $1', [input.ownerId]);
    await createGameEvent(tx, { id: `RESEARCH-STARTED-${input.correlationId}`, category: 'RESEARCH', eventType: 'RESEARCH_STARTED', gameDay: day, actorHouseId: senderHouse.rows[0]?.house_id ?? null, actorHumanId: input.ownerId, subjectType: 'RESEARCH_PROJECT', subjectId: projectId, title: 'Corporation research started', details: { projectId, technologyId: catalogEntry.id }, correlationId: input.correlationId });
    await createNotification(tx, { id: crypto.randomUUID(), humanId: input.ownerId, notificationType: 'technology', title: 'Corporation research started', body: `${input.name} is now being researched by your corporation.`, entityType: 'research_project', entityId: projectId, gameDay: day, correlationId: input.correlationId });
    return { ok: true, project: (await tx.query('SELECT * FROM corporation_research_projects WHERE id = $1', [projectId])).rows[0], correlationId: input.correlationId };
  });
}

export async function quoteResearchProject(repository: PostgresRepository, input: { ownerId: string; name: string }): Promise<Record<string, unknown>> {
  const day = (await readAuthoritativeGameTime(repository)).gameDay;
  await requireResearchJurisdiction(repository, input.ownerId);
  const catalog = await readTechnologyCatalog(repository, day);
  const entry = catalog.find((technology) => technology.name === input.name || technology.code === input.name);
  if (!entry) throw new Error('Technology is not available in the active catalog');
  await repository.query('SELECT earth_assert_technology_research_allowed($1, $2)', [entry.id, day + 1]);
  const membership = (await repository.query<{ corporation_id: string }>("SELECT ha.corporation_id FROM humans h JOIN house_affiliations ha ON ha.house_id = h.house_id WHERE h.id = $1 AND ha.status = 'ACTIVE' LIMIT 1", [input.ownerId])).rows[0];
  const activeProject = membership ? (await repository.query<{ id: string; status: string; progress_research_points: string }>(`SELECT p.id, p.status, p.progress_research_points::TEXT FROM corporation_research_projects p JOIN owner_registry o ON o.economic_id = p.corporation_economic_id WHERE o.id = $1 AND p.target_id = $2 AND p.status IN ('QUEUED','ACTIVE') LIMIT 1`, [membership.corporation_id, entry.id])).rows[0] : undefined;
  return {
    ok: true,
    technology: mapTechnologyCatalogRow(entry),
    quote: {
      researchCostUnits: entry.research_credit_cost_units,
      researchPointsRequired: entry.research_points_required,
      researchDurationGameDays: entry.research_duration_game_days,
      startsGameDay: day + 1,
      completesGameDay: day + 1 + Number(entry.research_duration_game_days),
      alreadyActive: activeProject ?? null,
    },
    generatedFrom: 'postgres-canonical-facts',
  };
}

export async function fundResearchProject(repository: PostgresRepository, input: { ownerId: string; amount: number; correlationId: string }): Promise<Record<string, unknown>> {
  void repository;
  void input;
  throw new Error('Research is funded at creation and completes after its scheduled whole-day duration');
}

// V5 research advances once per finalized day. Completion and access grant
// happen in the same transaction so retries cannot double-apply progression.
export async function advanceV5ResearchProjects(
  repository: PostgresRepository,
  gameDay: number,
): Promise<Record<string, unknown>> {
  const candidates = await repository.query<{ id: string }>(
    "SELECT id FROM corporation_research_projects WHERE target_type = 'TECHNOLOGY' AND status = 'ACTIVE' ORDER BY priority, id LIMIT 100",
  );
  let advanced = 0;
  let completed = 0;
  for (const candidate of candidates.rows) {
    await repository.transaction(async (tx) => {
      const project = (await tx.query<{
        id: string;
        corporation_economic_id: string;
        target_id: string;
        required_research_points: string;
        progress_research_points: string;
      }>(
        `SELECT id, corporation_economic_id, target_id,
                required_research_points::TEXT,
                progress_research_points::TEXT
           FROM corporation_research_projects
          WHERE id = $1 AND target_type = 'TECHNOLOGY' AND status = 'ACTIVE'
          FOR UPDATE`,
        [candidate.id],
      )).rows[0];
      if (!project) return;

      const next = BigInt(project.progress_research_points) + 1n;
      const required = BigInt(project.required_research_points);
      const progress = next < required ? next : required;
      await tx.query(
        'UPDATE corporation_research_projects SET progress_research_points = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
        [progress.toString(), project.id],
      );
      advanced += 1;
      if (progress < required) return;

      await tx.query(
        "UPDATE corporation_research_projects SET status = 'COMPLETED', completed_game_day = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2 AND status = 'ACTIVE'",
        [gameDay, project.id],
      );
      await tx.query(
        "SELECT earth_grant_corporation_technology_access($1, $2, 'RESEARCHED', $3, $4)",
        [project.corporation_economic_id, project.target_id, project.id, gameDay + 1],
      );
      completed += 1;
    });
  }
  return { ok: true, gameDay, projectsScanned: candidates.rows.length, advanced, completed };
}
