import type { PostgresRepository } from './repository';
import { mapTechnologyCatalogRow, normalizeResearchProject, type TechnologyCatalogRow } from './technology-postgres.ts';
import { listRankings as listRankingsSnapshot } from './rankings-postgres.ts';
import { priceUnitsToDisplayPrice } from './market-units.ts';
import { getConstitutionReadModel } from './constitutional-kernel-postgres.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';
import type { TechnologyWorkspace } from './technology-read-model.ts';
import { getEarthTechnologyFrontier } from './earth-technology-frontier-postgres.ts';
import { getAvailableGenerations } from './v5-generation-postgres.ts';

export { listEvents } from './read-models/events-read.ts';
export { listHistory } from './read-models/events-read.ts';
export { listNotifications, markNotificationRead, markAllNotificationsRead } from './read-models/notifications-read.ts';

export async function auditWorld(repository: PostgresRepository, humanId: string): Promise<Record<string, unknown>> {
  const [balances, ledger, succession, corporations, territories, market] = await Promise.all([
    repository.query('SELECT COUNT(*)::integer AS invalid FROM economic_accounts WHERE balance_units < 0'),
    repository.query('SELECT COUNT(*)::integer AS invalid FROM economic_entries WHERE delta_units = 0'),
    repository.query('SELECT COUNT(*)::integer AS count FROM succession_plans WHERE human_id = $1', [humanId]),
    repository.query('SELECT COUNT(*)::integer AS invalid FROM corporations c JOIN corporation_membership_summary s ON s.corporation_id = c.id WHERE c.member_count != s.active_house_count'),
    repository.query('SELECT COUNT(*)::integer AS invalid FROM territory_capacity_state WHERE total_slots < 0 OR used_slots < 0'),
    repository.query('SELECT check_name, invalid_count FROM earth_market_integrity_report()'),
  ]);
  const marketChecks = Object.fromEntries(market.rows.map((row: any) => [row.check_name, Number(row.invalid_count) === 0]));
  const checks = {
    balancesNonNegative: Number(balances.rows[0]?.invalid ?? 0) === 0,
    ledgerEntriesValid: Number(ledger.rows[0]?.invalid ?? 0) === 0,
    oneSuccessionPlanPerHuman: Number(succession.rows[0]?.count ?? 0) <= 1,
    corporationMemberCountsConsistent: Number(corporations.rows[0]?.invalid ?? 0) === 0,
    territoryCapacityValid: Number(territories.rows[0]?.invalid ?? 0) === 0,
    market: Object.values(marketChecks).every(Boolean),
  };
  return { ok: Object.values(checks).every(Boolean), checks };
}

export async function listInstitutions(repository: PostgresRepository): Promise<Record<string, unknown>> {
  const [institutions, territories, corporations, budgets, earthAccounts] = await Promise.all([
    repository.query('SELECT id, kind, name, status FROM institutions ORDER BY id'),
    repository.query('SELECT id, corporation_id, name, status FROM territories ORDER BY id'),
    repository.query('SELECT id, status FROM corporations ORDER BY id'),
    repository.query('SELECT id, institution_id, fiscal_period_id, category_id, authorized_units, committed_units, spent_units, status, rule_version FROM institution_budget_lines ORDER BY id'),
    repository.query(`SELECT a.account_type, a.balance_units::TEXT AS balance_units
                        FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id
                       WHERE o.id = 'EARTH' AND a.asset_id = 1 AND a.account_type IN ('TREASURY', 'OPERATIONS', 'RESERVE') AND a.status = 'ACTIVE'
                       ORDER BY a.account_type`),
  ]);
  const earth = Object.fromEntries(earthAccounts.rows.map((row) => [row.account_type.toLowerCase(), row.balance_units]));
  return { institutions: institutions.rows, community: [], territories: territories.rows, corporation: corporations.rows, membership: [], budgets: budgets.rows, earth: { treasury: earth.treasury ?? '0', budgets: budgets.rows.filter((row) => row.institution_id === 'EARTH') } };
}

export interface RankingsQueryOptions { category?: string; metric?: string; search?: string; limit?: number; offset?: number; currentHumanId?: string; }

export async function listRankings(repository: PostgresRepository, options: RankingsQueryOptions = {}): Promise<Record<string, unknown>> {
  return listRankingsSnapshot(repository, options);
}

export async function listTechnology(repository: PostgresRepository, humanId: string): Promise<TechnologyWorkspace> {
  const [projects, catalog, clock, frontier, corporation] = await Promise.all([
    repository.query(`SELECT p.* FROM corporation_research_projects p JOIN owner_registry o ON o.economic_id = p.corporation_economic_id JOIN house_affiliations ha ON ha.corporation_id = o.id JOIN humans h ON h.house_id = ha.house_id WHERE h.id = $1 AND ha.status = 'ACTIVE' ORDER BY p.id DESC`, [humanId]).catch(() => ({ rows: [] })),
    repository.query(`SELECT DISTINCT ON (tc.code)
      tc.id, tc.code, tc.name, tc.category, tc.description, tc.patentable,
      tc.patent_exclusivity_days,
      tc.credit_cost_units::TEXT AS research_credit_cost_units,
      tc.research_points_required::TEXT, tc.definition_version,
      tc.research_duration_game_days::TEXT,
      COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'effectType', e.effect_type, 'modifierFamily', e.modifier_family,
        'targetType', e.target_type, 'targetKey', e.target_key,
        'modifierBps', e.modifier_bps) ORDER BY e.id)
        FROM technology_effects e WHERE e.technology_id = tc.id), '[]'::JSONB) AS effects
      FROM technology_catalog tc
      WHERE tc.status = 'ACTIVE'
      ORDER BY tc.code, tc.definition_version DESC`).catch(() => ({ rows: [] })),
    readAuthoritativeGameTime(repository),
    getEarthTechnologyFrontier(repository),
    repository.query<{ economic_id: string }>(`SELECT o.economic_id
      FROM humans h
      JOIN house_affiliations ha ON ha.house_id = h.house_id AND ha.status = 'ACTIVE'
      JOIN owner_registry o ON o.id = ha.corporation_id AND o.owner_type = 'CORPORATION'
     WHERE h.id = $1 LIMIT 1`, [humanId]).catch(() => ({ rows: [] })),
  ]);
  const catalogRows = catalog.rows as TechnologyCatalogRow[];
  const catalogById = new Map(catalogRows.map((row) => [row.id, row]));
  const normalizedProjects = projects.rows.map((project) => normalizeResearchProject(
    project as Record<string, unknown>,
    clock.gameDay,
    catalogById.get(String((project as Record<string, unknown>).target_id)),
  ));
  const corporationEconomicId = corporation.rows[0]?.economic_id ?? null;
  const [access, budget] = corporationEconomicId
    ? await Promise.all([
      repository.query<{ technology_id: string; status: string }>(`SELECT technology_id, status
        FROM corporation_technology_access
        WHERE corporation_economic_id = $1 AND status = 'ACTIVE'
          AND effective_from_game_day <= $2
          AND (effective_to_game_day IS NULL OR effective_to_game_day >= $2)`, [corporationEconomicId, clock.gameDay]),
      repository.query<{ authorized_units: string; committed_units: string; spent_units: string; status: string }>(`SELECT l.authorized_units::TEXT, l.committed_units::TEXT,
          l.spent_units::TEXT, l.status
        FROM institution_budget_lines l
        JOIN budget_categories c ON c.id = l.category_id
        JOIN fiscal_periods fp ON fp.id = l.fiscal_period_id
        WHERE l.institution_id = $1
          AND c.institution_kind = 'CORPORATION'
          AND c.category_code = 'RESEARCH'
          AND fp.start_game_day <= $2 AND fp.end_game_day >= $2
          AND l.status = 'ACTIVE'
        ORDER BY fp.start_game_day DESC, l.id
        LIMIT 1`, [corporationEconomicId, clock.gameDay]),
    ])
    : [{ rows: [] }, { rows: [] }];
  const accessIds = new Set(access.rows.map((row) => String(row.technology_id)));
  const resolvedAccess = new Map<string, string>();
  if (corporationEconomicId) {
    const resolvedRows = await Promise.all(catalogRows.map(async (row) => {
      const result = await repository.query<{ access_reason: string | null }>(
        'SELECT access_reason FROM earth_resolve_corporation_technology_access($1, $2, $3)',
        [corporationEconomicId, row.id, clock.gameDay],
      ).catch(() => ({ rows: [] as Array<{ access_reason: string | null }> }));
      return [row.id, result.rows[0]?.access_reason ?? null] as const;
    }));
    for (const [technologyId, accessReason] of resolvedRows) {
      if (accessReason) resolvedAccess.set(technologyId, accessReason);
    }
  }
  const projectByTarget = new Map(normalizedProjects.map((project) => [
    String(project.target_id ?? project.targetId ?? ''), project,
  ]));
  const budgetRow = budget.rows[0];
  const budgetAvailable = budgetRow
    ? BigInt(budgetRow.authorized_units) - BigInt(budgetRow.committed_units) - BigInt(budgetRow.spent_units)
    : null;
  const researchBudget = budgetRow
    ? {
      authorizedUnits: String(budgetRow.authorized_units),
      committedUnits: String(budgetRow.committed_units),
      spentUnits: String(budgetRow.spent_units),
      availableUnits: String(budgetAvailable),
      status: String(budgetRow.status),
    }
    : null;
  const catalogWithViewerState = catalogRows.map((row) => {
    const project = projectByTarget.get(row.id);
    const cost = BigInt(row.research_credit_cost_units);
    const accessSource = resolvedAccess.get(row.id)
      ?? (accessIds.has(row.id) ? 'RESEARCHED' : null);
    const viewerStatus = accessSource || String(project?.status ?? '').toUpperCase() === 'COMPLETED'
      ? 'ADOPTED'
      : project && ['ACTIVE', 'QUEUED'].includes(String(project.status).toUpperCase())
        ? 'ACTIVE'
        : corporationEconomicId && budgetAvailable != null && budgetAvailable >= cost
          ? 'AVAILABLE'
          : 'LOCKED';
    const mapped = mapTechnologyCatalogRow(row);
    return { ...mapped, viewerStatus, accessSource, prerequisites: [] };
  });
  const frontierRows = await Promise.all((frontier.frontier as Array<Record<string, unknown>>).map(async (row) => {
    let corporationAccessibleGeneration: number | null = null;
    if (corporationEconomicId) {
      const available = await getAvailableGenerations(
        repository,
        String(row.domain_code ?? row.domain_id),
        corporationEconomicId,
        'CORPORATION',
        null,
        clock.gameDay,
      );
      corporationAccessibleGeneration = available.maxAccessibleGeneration;
    }
    const nextGeneration = row.next_generation_number == null ? null : Number(row.next_generation_number);
    return {
      id: String(row.domain_id),
      code: String(row.domain_code),
      name: String(row.domain_name),
      frontierGeneration: Number(row.max_generation_number ?? 1),
      effectiveFromGameDay: Number(row.effective_from_game_day ?? 1),
      nextGeneration,
      nextGenerationMinimumGameDay: row.next_generation_minimum_game_day == null ? null : Number(row.next_generation_minimum_game_day),
      corporationAccessibleGeneration,
      governanceStatus: nextGeneration == null ? 'NO_NEXT_GENERATION' : 'READY_FOR_GOVERNANCE',
    };
  }));
  return {
    catalog: catalogWithViewerState,
    projects: normalizedProjects as TechnologyWorkspace['projects'],
    adoptedCodes: catalogWithViewerState.filter((entry) => entry.viewerStatus === 'ADOPTED').map((entry) => entry.code),
    researchBudget,
    frontier: frontierRows as TechnologyWorkspace['frontier'],
  };
}

export async function listGovernanceProposals(repository: PostgresRepository): Promise<Record<string, unknown>> {
  const [proposals, ballots] = await Promise.all([
    repository.query(`SELECT p.*, COALESCE(h.display_name, 'Citizen') AS creator_name FROM proposals p LEFT JOIN humans h ON h.id = p.created_by_human_id ORDER BY p.closes_game_day ASC NULLS LAST, p.closes_game_minute ASC NULLS LAST, p.closes_at ASC`),
    repository.query('SELECT proposal_id, choice, ROUND(SUM(weight), 3) AS count FROM ballots GROUP BY proposal_id, choice'),
  ]);
  return { proposals: proposals.rows, voteCounts: ballots.rows };
}

export async function listGovernanceRules(repository: PostgresRepository): Promise<Record<string, unknown>> {
  const day = (await readAuthoritativeGameTime(repository)).gameDay;
  return getConstitutionReadModel(repository, { gameDay: day });
}

export async function getServiceStatus(repository: PostgresRepository, humanId: string): Promise<Record<string, unknown>> {
  const house = (await repository.query<{ house_id: string; territory_id: string }>(`SELECT h.house_id, r.territory_id FROM humans h JOIN house_residencies r ON r.house_id = h.house_id AND r.status = 'ACTIVE' AND r.residency_class = 'PRIMARY' WHERE h.id = $1 ORDER BY r.effective_from_game_day DESC LIMIT 1`, [humanId])).rows[0];
  if (!house) return { territoryId: null, provider: null, ratios: { housing: 0, utilities: 0, connectivity: 0, health: 0 }, needs: [], essentialServicesIndex: 0 };
  const assessments = (await repository.query<{ need_code: string; demand_units: string; allocated_units: string; shortfall_units: string; risk_level: string; game_day: number }>(`SELECT need_code, demand_units::TEXT, allocated_units::TEXT, shortfall_units::TEXT, risk_level, game_day FROM house_need_assessments WHERE house_id = $1 ORDER BY game_day DESC, need_code`, [house.house_id])).rows;
  const latestDay = assessments[0]?.game_day;
  const needs = assessments.filter((row) => row.game_day === latestDay).map((row) => {
    const demand = Number(row.demand_units); const allocated = Number(row.allocated_units);
    return { needCode: row.need_code, demandUnits: row.demand_units, allocatedUnits: row.allocated_units, shortfallUnits: row.shortfall_units, coverageRatio: demand > 0 ? Math.min(1, allocated / demand) : 1, risk: row.risk_level };
  });
  const coverage = Object.fromEntries(needs.map((need) => [need.needCode.toLowerCase(), need.coverageRatio]));
  const ratios = { housing: Number(coverage.housing ?? 0), utilities: Number(coverage.energy ?? 0), connectivity: Number(coverage.connectivity ?? 0), health: Number(coverage.health ?? 0) };
  return { territoryId: house.territory_id, provider: 'house-need-assessments', gameDay: latestDay ?? null, needs, ratios, status: Object.fromEntries(Object.entries(ratios).map(([key, value]) => [key, value >= 1 ? 'normal' : value >= .75 ? 'basic' : 'critical'])), essentialServicesIndex: Math.min(...Object.values(ratios)) };
}

/** Public legacy read model. It deliberately exposes only memorial facts, never account data. */
export async function listPantheonOfAchievements(repository: PostgresRepository, query: { search?: string; limit?: number } = {}): Promise<Record<string, unknown>> {
  const search = query.search?.trim() ?? '';
  const requestedLimit = Number(query.limit ?? 100);
  const limit = Number.isFinite(requestedLimit) ? Math.min(100, Math.max(1, Math.trunc(requestedLimit))) : 100;
  const [deceased, living, houses] = await Promise.all([
    repository.query(`SELECT h.id AS human_id, h.display_name, h.house_id, d.house_name,
                             h.birth_game_day, h.death_game_day, h.age_years,
                             h.final_legacy, h.standing AS final_standing,
                             NULL::TEXT AS cause_of_death, NULL::TEXT AS epitaph,
                             successor.display_name AS successor_name
                        FROM humans h JOIN houses d ON d.id = h.house_id
                        LEFT JOIN LATERAL (
                          SELECT successor_h.display_name
                            FROM succession_events se
                            JOIN humans successor_h ON successor_h.id = se.successor_human_id
                           WHERE se.predecessor_human_id = h.id
                           ORDER BY se.effective_game_day DESC, se.id DESC
                           LIMIT 1
                        ) successor ON TRUE
                       WHERE h.status = 'DECEASED'
                         AND ($1 = '' OR h.display_name ILIKE '%' || $1 || '%' OR d.house_name ILIKE '%' || $1 || '%')
                       ORDER BY h.death_game_day DESC NULLS LAST, h.id
                       LIMIT $2`, [search, limit]),
    repository.query(`SELECT h.id, h.display_name, h.house_id, d.house_name, h.age_years,
                             h.standing, h.final_legacy AS legacy,
                             (h.final_legacy + h.standing) AS composite_legacy_score
                        FROM humans h JOIN houses d ON d.id = h.house_id
                       WHERE h.status = 'ACTIVE'
                       ORDER BY composite_legacy_score DESC, h.id
                       LIMIT 100`),
    repository.query(`SELECT houses.id, houses.house_name, houses.motto, houses.dynasty_legacy, houses.generation, houses.status,
                             (SELECT MIN(hum.birth_game_day) FROM humans hum WHERE hum.house_id = houses.id) AS founded_game_day,
                             (SELECT MAX(hum.death_game_day) FROM humans hum WHERE hum.house_id = houses.id AND hum.status = 'DECEASED') AS extinct_game_day,
                             (SELECT MAX(hum.death_game_day) - MIN(hum.birth_game_day) FROM humans hum WHERE hum.house_id = houses.id) AS lifespan_days,
                             (SELECT COUNT(*)::INTEGER FROM humans hum WHERE hum.house_id = houses.id AND hum.status = 'DECEASED') AS deceased_count,
                             0::INTEGER AS active_member_count,
                             TRUE AS is_extinct
                        FROM houses WHERE status IN ('ACTIVE', 'SUSPENDED')
                         AND EXISTS (SELECT 1 FROM humans hum WHERE hum.house_id = houses.id)
                         AND NOT EXISTS (SELECT 1 FROM humans hum WHERE hum.house_id = houses.id AND hum.status = 'ACTIVE')
                         AND ($1 = '' OR houses.house_name ILIKE '%' || $1 || '%')
                       ORDER BY extinct_game_day DESC NULLS LAST, houses.id
                       LIMIT $2`, [search, limit]),
  ]);
  return {
    deceasedPantheon: deceased.rows,
    livingLeaders: living.rows,
    houses: houses.rows,
    dynasticHouses: houses.rows,
    game_day: (await readAuthoritativeGameTime(repository)).gameDay,
    search,
    limit,
    generatedFrom: 'postgres-canonical-facts',
  };
}

export async function listCemeteryProfiles(
  repository: PostgresRepository,
  query: { search?: string; house?: string; dynasty?: string; limit?: number },
): Promise<Record<string, unknown>> {
  const requestedLimit = Number(query.limit ?? 50);
  const limit = Number.isFinite(requestedLimit) ? Math.min(100, Math.max(1, Math.trunc(requestedLimit))) : 50;
  const search = query.search?.trim() ?? '';
  const house = query.house?.trim() ?? '';
  const dynasty = query.dynasty?.trim() ?? '';
  const result = await repository.query(`SELECT h.id AS human_id, h.display_name, h.house_id,
                                                d.house_name, d.motto, d.generation,
                                                h.birth_game_day, h.death_game_day, h.age_years,
                                                h.final_legacy, h.standing AS final_standing,
                                                NULL::TEXT AS successor_name
                                           FROM humans h JOIN houses d ON d.id = h.house_id
                                          WHERE h.status = 'DECEASED'
                                            AND ($1 = '' OR h.display_name ILIKE '%' || $1 || '%' OR d.house_name ILIKE '%' || $1 || '%')
                                            AND ($2 = '' OR d.house_name ILIKE '%' || $2 || '%')
                                            AND ($3 = '' OR d.house_name ILIKE '%' || $3 || '%')
                                          ORDER BY h.death_game_day DESC NULLS LAST, h.id
                                          LIMIT $4`, [search, house, dynasty, limit]);
  return { profiles: result.rows, cemetery: result.rows, generatedFrom: 'postgres-canonical-facts' };
}

export async function listMarketPriceHistory(repository: PostgresRepository, product: string, limitDays = 30): Promise<Record<string, unknown>> {
  const normalizedProduct = product.trim().toLowerCase();
  const requestedDays = Number(limitDays);
  const days = Number.isFinite(requestedDays) ? Math.min(100, Math.max(1, Math.trunc(requestedDays))) : 30;
  const result = await repository.query(`SELECT i.symbol, c.period_id, c.open_price_units::TEXT,
                                                c.high_price_units::TEXT, c.low_price_units::TEXT,
                                                c.close_price_units::TEXT, c.volume_units::TEXT, c.fill_count
                                           FROM market_instruments i
                                           JOIN market_candles c ON c.instrument_id = i.id
                                          WHERE i.symbol = $1 AND c.interval_kind = 'daily'
                                          ORDER BY c.period_id DESC
                                          LIMIT $2`, [`SPOT-${normalizedProduct.toUpperCase()}`, days]);
  const history = result.rows.map((row: any) => ({
    periodId: row.period_id,
    price: priceUnitsToDisplayPrice(row.close_price_units),
    open: priceUnitsToDisplayPrice(row.open_price_units),
    high: priceUnitsToDisplayPrice(row.high_price_units),
    low: priceUnitsToDisplayPrice(row.low_price_units),
    volume: String(row.volume_units ?? '0'),
    fillCount: Number(row.fill_count ?? 0),
  }));
  return { product: normalizedProduct, history, generatedFrom: 'postgres-canonical-facts' };
}
