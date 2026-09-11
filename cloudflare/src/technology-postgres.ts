import type { PostgresRepository } from './repository.ts';
import { moneyToCents } from './money.ts';

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
  status: string;
  definition_version: number;
  effective_from_game_day: number;
  effective_to_game_day: number | null;
  effects: Array<Record<string, unknown>>;
};

export function mapTechnologyCatalogRow(row: TechnologyCatalogRow): Record<string, unknown> {
  return {
    ...row,
    researchCostUnits: row.research_credit_cost_units,
    researchPointsRequired: row.research_points_required,
    effects: row.effects ?? [],
    kind: 'approved_capability',
    tradeable: false,
    playerCreated: false,
  };
}

async function readTechnologyCatalog(tx: PostgresRepository, gameDay?: number): Promise<TechnologyCatalogRow[]> {
  const day = gameDay ?? 0;
  const result = await tx.query<TechnologyCatalogRow>(`SELECT DISTINCT ON (tc.code) tc.id, tc.code, tc.name, tc.category, tc.description,
      patentable, patent_exclusivity_days, research_credit_cost_units::TEXT,
      research_points_required::TEXT, status, definition_version,
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
  const membership = await tx.query<{ corporation_id: string | null }>('SELECT corporation_id FROM memberships WHERE human_id = $1', [ownerId]);
  if (!membership.rows[0]?.corporation_id) throw new Error('Research requires active corporation membership');
}

export async function createResearchProject(repository: PostgresRepository, input: { ownerId: string; name: string; budget: number; focus: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    await requireResearchJurisdiction(tx, input.ownerId);
    const membership = await tx.query<{ corporation_id: string }>('SELECT corporation_id FROM memberships WHERE human_id = $1', [input.ownerId]);
    const corporationId = membership.rows[0].corporation_id;
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
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
        AND service.asset_id = 1 AND service.account_type = 4 AND service.status = 'active'
      WHERE payer.asset_id = 1 AND payer.account_type IN (3, 4)
        AND payer.status = 'active'
      ORDER BY payer.is_default_settlement DESC, payer.account_type, payer.id
      LIMIT 1`, [corporationId]);
    if (!fundingAccounts.rows[0]) throw new Error('Corporation V2 funding account or system research account is not provisioned');
    const funding = await tx.query<{ transaction_id: string; created: boolean }>(
      `SELECT transaction_id, created FROM earth_post_transaction($1,$2,1439,'RESEARCH_FUNDING','CORPORATION_RESEARCH',$3,$4,$5::jsonb)`,
      [input.correlationId, day, projectId, `technology-catalog-v${catalogEntry.definition_version}`, JSON.stringify([
        { account_id: fundingAccounts.rows[0].debit_account_id, delta: (-BigInt(budgetCents)).toString(), reason_code: 'CORPORATION_RESEARCH_FUNDING' },
        { account_id: fundingAccounts.rows[0].research_account_id, delta: BigInt(budgetCents).toString(), reason_code: 'CORPORATION_RESEARCH_FUNDING' },
      ])],
    );
    const fundingTransactionId = funding.rows[0]?.transaction_id;
    if (!fundingTransactionId) throw new Error('Research funding transaction was not created');
    await tx.query(`INSERT INTO corporation_research_projects
      (id, corporation_economic_id, target_type, target_id, definition_version,
       required_research_points, progress_research_points, credit_cost_units,
       priority, status, started_game_day, funding_transaction_id, correlation_id, definition_snapshot)
      VALUES ($1,$2,'TECHNOLOGY',$3,$4,$5,0, $6,100,'ACTIVE',$7,$8,$9,$10::jsonb)`,
      [projectId, corporationOwner.rows[0].economic_id, catalogEntry.id, `technology-catalog-v${catalogEntry.definition_version}`, catalogEntry.research_points_required, catalogEntry.research_credit_cost_units, day, fundingTransactionId, input.correlationId, JSON.stringify({ technologyId: catalogEntry.id, code: catalogEntry.code, name: catalogEntry.name, definitionVersion: catalogEntry.definition_version, researchCreditCostUnits: catalogEntry.research_credit_cost_units, researchPointsRequired: catalogEntry.research_points_required, effects: catalogEntry.effects, patentable: catalogEntry.patentable, patentExclusivityDays: catalogEntry.patent_exclusivity_days })]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [crypto.randomUUID(), input.ownerId, 'technology', 'Corporation research started', `${input.name} is now being researched by your corporation.`, projectId]);
    return { ok: true, project: (await tx.query('SELECT * FROM corporation_research_projects WHERE id = $1', [projectId])).rows[0], correlationId: input.correlationId };
  });
}

export async function fundResearchProject(repository: PostgresRepository, input: { ownerId: string; amount: number; correlationId: string }): Promise<Record<string, unknown>> {
  void repository;
  void input;
  throw new Error('Research is funded at creation and completes after its scheduled whole-day duration');
}
