import type { PostgresRepository } from './repository.ts';
import { listCommunities } from './communities-postgres.ts';
import { listWorldConditions } from './world-conditions-postgres.ts';
import { listRankings } from './rankings-postgres.ts';
import { listOrganizations } from './organizations-postgres.ts';
import { generateDecisionQueue } from './decision-queue.ts';
import { listTechnology } from './read-postgres.ts';
import { listCorporationBuildingResearch } from './corporation-building-research-postgres.ts';
import { assetUnitScale } from './market-model.ts';
import { priceUnitsToDisplayPrice, unitsToDisplayQuantity } from './market-units.ts';
import { marketFeeRate } from './market-rules.ts';

export async function worldSnapshot(repository: PostgresRepository, viewerId?: string, viewerHouseId?: string): Promise<Record<string, unknown>> {
  const [world, institutions, humans, assets, communities, serviceAssessments, conditions, viewer, catalog, buildings, accounts, residency, obligations, proposals, rankings, territories, corporation, organizations, governanceRules, taxRules] = await Promise.all([
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
                                             c.operating_credit_units,
                                             COALESCE(latest.utilization_bps, 10000) AS utilization_bps,
                                             latest.game_day AS latest_settlement_game_day
                                        FROM buildings b
                                        JOIN owner_registry o ON o.economic_id = b.owner_economic_id
                                        JOIN building_catalog c ON c.id = b.catalog_id
                                        LEFT JOIN LATERAL (
                                          SELECT utilization_bps, game_day
                                            FROM building_settlement_journals
                                           WHERE building_id = b.id
                                           ORDER BY game_day DESC
                                           LIMIT 1
                                        ) latest ON TRUE
                                       WHERE o.id = $1
                                       ORDER BY b.status, b.id`, [viewerHouseId]) : Promise.resolve({ rows: [] }),
    viewerHouseId ? repository.query(`SELECT a.account_type, asset.code, a.balance_units::TEXT AS balance_units
                                        FROM economic_accounts a
                                        JOIN owner_registry owner ON owner.economic_id = a.owner_economic_id
                                        JOIN economic_assets asset ON asset.id = a.asset_id
                                       WHERE owner.id = $1 AND a.status = 'ACTIVE'
                                       ORDER BY asset.id, a.account_type`, [viewerHouseId]) : Promise.resolve({ rows: [] }),
    viewerHouseId ? repository.query(`SELECT r.territory_id, r.residency_class, r.status, r.effective_from_game_day,
                                             t.name AS territory_name, t.corporation_id,
                                             COALESCE(g.governing_institution_id, t.corporation_id) AS governing_institution_id,
                                             i.name AS corporation_name
                                        FROM house_residencies r
                                        JOIN territories t ON t.id = r.territory_id
                                        LEFT JOIN territory_governance g ON g.territory_id = t.id AND g.status = 'ACTIVE'
                                        LEFT JOIN institutions i ON i.id = COALESCE(g.governing_institution_id, t.corporation_id)
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
    listRankings(repository),
    repository.query(`SELECT id, corporation_id, name, territory_type, status, is_primary, created_game_day
                        FROM territories
                       WHERE status IN ('ACTIVE', 'UNGOVERNED')
                       ORDER BY corporation_id, is_primary DESC, id`),
    viewerHouseId
      ? repository.query(`SELECT c.id, i.name, c.status, c.charter_version, c.admission_policy,
                                 c.created_game_day,
                                 (SELECT COUNT(*)::INTEGER FROM territories t WHERE t.corporation_id = c.id AND t.status = 'ACTIVE') AS territory_count,
                                 (SELECT COUNT(*)::INTEGER FROM house_affiliations ha WHERE ha.corporation_id = c.id AND ha.status = 'ACTIVE') AS member_count,
                                 (SELECT t.name FROM territories t WHERE t.corporation_id = c.id AND t.is_primary = TRUE AND t.status = 'ACTIVE' LIMIT 1) AS primary_territory_name
                            FROM house_affiliations ha
                            JOIN corporations c ON c.id = ha.corporation_id
                            JOIN institutions i ON i.id = c.id
                           WHERE ha.house_id = $1 AND ha.status = 'ACTIVE'
                           LIMIT 1`, [viewerHouseId])
      : Promise.resolve({ rows: [] }),
    listOrganizations(repository, viewerHouseId ?? ''),
    repository.query(`SELECT id, institution_id, name, category, value_json, quorum_threshold,
                             approval_threshold, voting_period_days, implementation_delay_days,
                             version, status, created_by, effective_from_game_day, effective_to_game_day
                        FROM governance_rules
                       WHERE status IN ('active', 'superseded')
                       ORDER BY institution_id, category, version DESC, id`),
    repository.query(`SELECT scope, category, minimum_rate_bps, maximum_rate_bps,
                             allowed_tax_base_definitions, beneficiary_scope, rules_version
                        FROM tax_governance_rules
                       ORDER BY scope, category`),
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
  const [technology, corporationBuildingResearch, marketInstruments, marketOrders] = await Promise.all([
    viewerId ? listTechnology(repository, viewerId) : Promise.resolve({ catalog: [], projects: [] }),
    viewerId ? listCorporationBuildingResearch(repository, viewerId) : Promise.resolve({ corporationId: null, projects: [], unlocks: [] }),
    repository.query(`SELECT i.id, i.symbol, i.asset_id, i.rules_version, i.genesis_reference_price_units::TEXT,
                             s.last_clearing_price_units::TEXT, s.best_bid_units::TEXT, s.best_ask_units::TEXT,
                             s.open_buy_units::TEXT, s.open_sell_units::TEXT, s.updated_at
                        FROM market_instruments i
                        LEFT JOIN market_instrument_state s ON s.instrument_id = i.id
                       WHERE i.instrument_type = 'SPOT' AND i.status = 'ACTIVE'
                       ORDER BY i.symbol`),
    repository.query(`SELECT o.id, i.symbol, o.side, o.status, o.quantity_units::TEXT,
                             o.remaining_units::TEXT, o.limit_price_units::TEXT,
                             o.rules_version, o.good_til_game_day, o.created_at,
                             i.asset_id
                        FROM market_orders o
                        JOIN market_instruments i ON i.id = o.instrument_id
                       WHERE o.status IN ('OPEN', 'PARTIAL')
                         AND ($1::TEXT IS NOT NULL AND o.owner_economic_id =
                              (SELECT economic_id FROM owner_registry WHERE id = $1))
                       ORDER BY o.created_at DESC LIMIT 500`, [viewerHouseId]),
  ]);
  const marketProducts = Object.fromEntries(marketInstruments.rows.map((row: any) => {
    const product = String(row.symbol).replace(/^SPOT-/, '').toLowerCase();
    const priceUnits = row.last_clearing_price_units ?? row.genesis_reference_price_units;
    return [product, {
      product,
      price: priceUnits == null ? null : priceUnitsToDisplayPrice(String(priceUnits)),
      priceAvailable: priceUnits != null,
      bestBid: row.best_bid_units == null ? null : priceUnitsToDisplayPrice(String(row.best_bid_units)),
      bestAsk: row.best_ask_units == null ? null : priceUnitsToDisplayPrice(String(row.best_ask_units)),
      supply: unitsToDisplayQuantity(String(row.open_sell_units ?? '0'), assetUnitScale(Number(row.asset_id ?? 2))),
      demand: unitsToDisplayQuantity(String(row.open_buy_units ?? '0'), assetUnitScale(Number(row.asset_id ?? 2))),
      rulesVersion: row.rules_version,
      updatedAt: row.updated_at,
    }];
  }));
  const market = {
    products: marketProducts,
    orders: marketOrders.rows.map((row: any) => {
      const quantity = unitsToDisplayQuantity(String(row.quantity_units ?? '0'), assetUnitScale(Number(row.asset_id ?? 2)));
      const remaining = unitsToDisplayQuantity(String(row.remaining_units ?? '0'), assetUnitScale(Number(row.asset_id ?? 2)));
      return {
        id: row.id,
        product: String(row.symbol).replace(/^SPOT-/, '').toLowerCase(),
        side: String(row.side).toLowerCase(),
        status: row.status,
        quantity,
        filledQuantity: quantity - remaining,
        remainingQuantity: remaining,
        limitPrice: priceUnitsToDisplayPrice(String(row.limit_price_units ?? '0')),
        rulesVersion: row.rules_version,
        goodTilGameDay: row.good_til_game_day,
        createdAt: row.created_at,
      };
    }),
    feeRate: Number(await marketFeeRate(repository, viewerId)),
    gameDay,
    generatedFrom: 'postgres-canonical-facts',
  };
  const needs = serviceAssessments.rows.filter((row) => row.game_day === latestServiceDay);
  const decisionQueue = generateDecisionQueue({
    gameDay,
    house: { successor_id: null },
    resources,
    finance: { unpaid_tax: obligations.rows.length, debt: obligations.rows.length },
    territory: capacity ? { ...capacity, id: capacity.territory_id, residents: capacity.active_house_count } : undefined,
    needs,
    proposals: proposals.rows,
    market: Object.values(marketProducts),
    buildings: buildings.rows,
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
    territories: territories.rows,
    organizations: organizations['organizations'] ?? [],
    corporation: corporation.rows[0] ?? null,
    humans: humans.rows,
    economicAssets: assets.rows,
    communities: communities.communities,
    serviceStatus,
    serviceNeeds: needs,
    buildings: buildings.rows,
    buildingCatalog: catalog.rows,
    technology: { catalog: technology.catalog, projects: technology.projects },
    corporationBuildingResearch,
    corporateResearch: technology.projects,
    market,
    finance: { balance: wallet?.balance_units ?? '0', obligations: obligations.rows },
    taxRules: taxRules.rows,
    personalFinance: { balance: wallet?.balance_units ?? '0', obligations: obligations.rows },
    membership: territory ? {
      territory_id: territory.territory_id,
      territory_name: territory.territory_name,
      residency_class: territory.residency_class,
      corporation_id: territory.corporation_id ?? corporation.rows[0]?.id ?? null,
      corporation_name: territory.corporation_name ?? corporation.rows[0]?.name ?? null,
    } : null,
    governance: { proposals: proposals.rows, rules: governanceRules.rows },
    districtZoning: capacity ?? {},
    decisionQueue,
    rankings,
    worldConditions: exposedConditions,
  };
}
