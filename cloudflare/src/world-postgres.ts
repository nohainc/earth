import type { PostgresRepository } from './repository.ts';
import { listCommunities } from './communities-postgres.ts';
import { listWorldConditions } from './world-conditions-postgres.ts';
import { generateDecisionQueue } from './decision-queue.ts';

export async function worldSnapshot(repository: PostgresRepository, viewerId?: string, viewerHouseId?: string): Promise<Record<string, unknown>> {
  const [world, institutions, humans, assets, communities, serviceAssessments, conditions, viewer, catalog, buildings, accounts, residency, obligations, proposals] = await Promise.all([
    repository.query("SELECT id, game_day, game_minute, world_seed, status FROM world_state WHERE id = 'WORLD'"),
    repository.query('SELECT id, kind, name, status FROM institutions ORDER BY id'),
    repository.query("SELECT id, house_id, display_name, age_years, standing, final_legacy, status FROM humans WHERE status = 'ACTIVE' ORDER BY id"),
    repository.query('SELECT code, asset_kind FROM economic_assets ORDER BY id'),
    listCommunities(repository, viewerHouseId),
    viewerHouseId ? repository.query<{ need_code: string; risk_level: string; game_day: number }>(`SELECT need_code, risk_level, game_day FROM house_need_assessments WHERE house_id = $1 ORDER BY game_day DESC, need_code`, [viewerHouseId]) : Promise.resolve({ rows: [] as { need_code: string; risk_level: string; game_day: number }[] }),
    listWorldConditions(repository),
    viewerId ? repository.query(`SELECT h.id, h.house_id, h.display_name, h.age_years, h.standing, h.final_legacy, h.status,
                                        hs.house_name, hs.motto, hs.generation, hs.dynasty_legacy
                                   FROM humans h JOIN houses hs ON hs.id = h.house_id
                                  WHERE h.id = $1`, [viewerId]) : Promise.resolve({ rows: [] }),
    repository.query(`SELECT c.id, c.code, c.code AS building_type, c.family_code, c.tier, c.tier_formula_version,
                             c.economic_role, c.ownership_scope, lower(c.ownership_scope) AS ownership_class,
                             c.construction_credit_units, c.construction_minutes,
                             c.operating_credit_units, c.service_type, c.service_capacity_units,
                             c.slot_footprint, c.definition_version,
                             COALESCE(jsonb_agg(jsonb_build_object(
                               'assetId', f.asset_id,
                               'constructionUnits', f.construction_units,
                               'operatingInputUnits', f.operating_input_units,
                               'operatingOutputUnits', f.operating_output_units
                             ) ORDER BY f.asset_id) FILTER (WHERE f.asset_id IS NOT NULL), '[]'::jsonb) AS resource_flows
                        FROM building_catalog c
                        LEFT JOIN building_catalog_resource_flows f ON f.catalog_id = c.id
                       GROUP BY c.id, c.code, c.family_code, c.tier, c.tier_formula_version,
                                c.economic_role, c.ownership_scope, c.construction_credit_units,
                                c.construction_minutes, c.operating_credit_units, c.service_type,
                                c.service_capacity_units, c.slot_footprint, c.definition_version
                       ORDER BY c.code, c.tier, c.id`),
    viewerHouseId ? repository.query(`SELECT b.id, b.territory_id, b.catalog_id, b.status, b.started_game_day,
                                             c.code, c.code AS building_type, c.tier, c.economic_role,
                                             c.ownership_scope, lower(c.ownership_scope) AS ownership_class,
                                             c.service_type, c.service_capacity_units, c.slot_footprint,
                                             c.operating_credit_units
                                        FROM buildings b
                                        JOIN owner_registry o ON o.economic_id = b.owner_economic_id
                                        JOIN building_catalog c ON c.id = b.catalog_id
                                       WHERE o.id = $1
                                       ORDER BY b.status, b.id`, [viewerHouseId]) : Promise.resolve({ rows: [] }),
    viewerHouseId ? repository.query(`SELECT a.account_type, asset.code, a.balance_units::TEXT AS balance_units
                                        FROM economic_accounts a
                                        JOIN owner_registry owner ON owner.economic_id = a.owner_economic_id
                                        JOIN economic_assets asset ON asset.id = a.asset_id
                                       WHERE owner.id = $1 AND a.status = 'ACTIVE'
                                       ORDER BY asset.id, a.account_type`, [viewerHouseId]) : Promise.resolve({ rows: [] }),
    viewerHouseId ? repository.query(`SELECT r.territory_id, r.residency_class, r.status, r.effective_from_game_day,
                                             t.name AS territory_name
                                        FROM house_residencies r JOIN territories t ON t.id = r.territory_id
                                       WHERE r.house_id = $1 AND r.status = 'ACTIVE'
                                       ORDER BY r.effective_from_game_day DESC`, [viewerHouseId]) : Promise.resolve({ rows: [] }),
    viewerHouseId ? repository.query(`SELECT id, obligation_type, principal_due_units::TEXT AS principal_due_units,
                                             interest_due_units::TEXT AS interest_due_units,
                                             status, due_game_day
                                        FROM financial_obligations
                                       WHERE debtor_economic_id = (SELECT economic_id FROM owner_registry WHERE id = $1)
                                         AND status IN ('DUE', 'PARTIAL', 'ARREARS')
                                       ORDER BY due_game_day, id LIMIT 100`, [viewerHouseId]) : Promise.resolve({ rows: [] }),
    repository.query(`SELECT id, action_type AS title, status, created_game_day
                        FROM proposals
                       WHERE status IN ('OPEN', 'VOTING', 'PASSED')
                       ORDER BY created_game_day DESC, id LIMIT 100`),
  ]);
  const latestServiceDay = serviceAssessments.rows[0]?.game_day;
  const serviceStatus = Object.fromEntries(serviceAssessments.rows.filter((row) => row.game_day === latestServiceDay).map((row) => [row.need_code, row.risk_level === 'NORMAL' ? 'normal' : row.risk_level === 'WATCH' ? 'basic' : 'critical']));
  const gameDay = Number(world.rows[0]?.game_day ?? 1);
  const gameMinute = Number(world.rows[0]?.game_minute ?? 0);
  const house = viewer.rows[0] ?? null;
  const resources = Object.fromEntries(accounts.rows
    .filter((row: any) => row.code !== 'CREDIT')
    .filter((row: any) => row.account_type === 'INVENTORY')
    .map((row: any) => [String(row.code).toLowerCase(), String(row.balance_units)]));
  if (resources.material != null && resources.materials == null) resources.materials = resources.material;
  const wallet = accounts.rows.find((row: any) => row.code === 'CREDIT' && row.account_type === 'WALLET');
  const territory = residency.rows.find((row: any) => row.residency_class === 'PRIMARY') ?? residency.rows[0];
  const exposedConditions = conditions.conditions.map((condition: any) => {
    const scopeType = condition.scope?.type;
    const scopeId = condition.scope?.id;
    const exposure = scopeType === 'WORLD'
      ? 'WORLDWIDE'
      : scopeType === 'TERRITORY' && scopeId === territory?.territory_id
        ? 'YOUR_TERRITORY'
        : scopeType === 'ORGANIZATION'
          ? 'ORGANIZATION_SCOPED'
          : 'OTHER_TERRITORY';
    return { ...condition, exposure };
  });
  const capacity = territory?.territory_id ? (await repository.query(`SELECT territory_id, active_house_count, house_capacity, population_capacity, private_slot_capacity, public_slot_capacity, private_slots_used, public_slots_used, housing_capacity, health_capacity, energy_capacity, connectivity_capacity, service_capacity FROM territory_capacity_state WHERE territory_id = $1`, [territory.territory_id])).rows[0] : null;
  const needs = serviceAssessments.rows.filter((row) => row.game_day === latestServiceDay);
  const decisionQueue = generateDecisionQueue({
    gameDay,
    house: { successor_id: null },
    resources,
    finance: { unpaid_tax: obligations.rows.length, debt: obligations.rows.length },
    territory: capacity ? { ...capacity, id: capacity.territory_id, residents: capacity.active_house_count } : undefined,
    needs,
    proposals: proposals.rows,
  });
  return {
    ok: true,
    viewerId: viewerId ?? null,
    world: world.rows[0] ?? null,
    clock: { day: gameDay, minute: gameMinute },
    human: house,
    resources,
    resourceFlows: {},
    institutions: institutions.rows,
    humans: humans.rows,
    economicAssets: assets.rows,
    communities: communities.communities,
    serviceStatus,
    serviceNeeds: needs,
    buildings: buildings.rows,
    buildingCatalog: catalog.rows,
    finance: { balance: wallet?.balance_units ?? '0', obligations: obligations.rows },
    personalFinance: { balance: wallet?.balance_units ?? '0', obligations: obligations.rows },
    membership: territory ? { territory_id: territory.territory_id, territory_name: territory.territory_name, residency_class: territory.residency_class } : null,
    districtZoning: capacity ?? {},
    decisionQueue,
    worldConditions: exposedConditions,
  };
}
