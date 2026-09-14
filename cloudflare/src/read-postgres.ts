import type { PostgresRepository } from './repository';
import { mapTechnologyCatalogRow } from './technology-postgres.ts';

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
  const [institutions, territories, corporations, budgets] = await Promise.all([
    repository.query('SELECT id, kind, name, status FROM institutions ORDER BY id'),
    repository.query('SELECT id, corporation_id, name, status FROM territories ORDER BY id'),
    repository.query('SELECT id, status FROM corporations ORDER BY id'),
    repository.query('SELECT id, institution_id, fiscal_period_id, category_id, authorized_units, committed_units, spent_units, status, rule_version FROM institution_budget_lines ORDER BY id'),
  ]);
  return { institutions: institutions.rows, community: [], territories: territories.rows, corporation: corporations.rows, membership: [], budgets: budgets.rows };
}

export interface RankingsQueryOptions { category?: string; metric?: string; search?: string; limit?: number; offset?: number; currentHumanId?: string; }

export async function listRankings(repository: PostgresRepository, options: RankingsQueryOptions = {}): Promise<Record<string, unknown>> {
  const limit = Math.min(100, Math.max(1, options.limit ?? 50));
  const [corporations, territories, technologies] = await Promise.all([
    repository.query('SELECT c.id, c.name, c.status, c.member_count, COALESCE(a.balance_units, 0)::text AS treasury FROM corporations c LEFT JOIN owner_registry o ON o.id = c.id LEFT JOIN economic_accounts a ON a.owner_economic_id = o.economic_id AND a.asset_id = 1 AND a.account_type = \'TREASURY\' AND a.status = \'ACTIVE\' ORDER BY c.id LIMIT $1', [limit]).catch(() => ({ rows: [] })),
    repository.query('SELECT t.id, t.corporation_id, t.name, t.status, s.total_slots, s.used_slots, s.available_slots FROM territories t LEFT JOIN territory_capacity_state s ON s.territory_id = t.id ORDER BY t.id LIMIT $1', [limit]).catch(() => ({ rows: [] })),
    repository.query('SELECT tc.id, tc.code, tc.name FROM technology_catalog tc ORDER BY tc.code LIMIT $1', [limit]).catch(() => ({ rows: [] })),
  ]);
  return { ok: true, corporations: corporations.rows, territories: territories.rows, rankings: [], wealth: [], technologies: technologies.rows, citizens: [], houses: [], dynasticHouses: [], generatedFrom: 'planetscale-postgres' };
}

export async function listTechnology(repository: PostgresRepository, humanId: string): Promise<Record<string, unknown>> {
  const [projects, catalog] = await Promise.all([
    repository.query(`SELECT p.* FROM corporation_research_projects p JOIN owner_registry o ON o.economic_id = p.corporation_economic_id JOIN house_affiliations ha ON ha.corporation_id = o.id JOIN humans h ON h.house_id = ha.house_id WHERE h.id = $1 AND ha.status = 'ACTIVE' ORDER BY p.id DESC`, [humanId]).catch(() => ({ rows: [] })),
    repository.query('SELECT tc.id, tc.code, tc.name, tc.patentable, tc.credit_cost_units::TEXT AS research_credit_cost_units, tc.research_points_required::TEXT, tc.definition_version FROM technology_catalog tc ORDER BY tc.code').catch(() => ({ rows: [] })),
  ]);
  return { catalog: catalog.rows.map(mapTechnologyCatalogRow), projects: projects.rows };
}

export async function listGovernanceProposals(repository: PostgresRepository): Promise<Record<string, unknown>> {
  const [proposals, ballots] = await Promise.all([
    repository.query(`SELECT p.*, COALESCE(h.display_name, 'Citizen') AS creator_name FROM proposals p LEFT JOIN humans h ON h.id = p.created_by_human_id ORDER BY p.closes_game_day ASC NULLS LAST, p.closes_game_minute ASC NULLS LAST, p.closes_at ASC`),
    repository.query('SELECT proposal_id, choice, ROUND(SUM(weight), 3) AS count FROM ballots GROUP BY proposal_id, choice'),
  ]);
  return { proposals: proposals.rows, voteCounts: ballots.rows };
}

export async function listGovernanceRules(repository: PostgresRepository): Promise<Record<string, unknown>> {
  return { rules: (await repository.query("SELECT * FROM governance_rules WHERE status IN ('active','superseded') ORDER BY institution_id, category, version DESC")).rows };
}

export async function getServiceStatus(repository: PostgresRepository, humanId: string): Promise<Record<string, unknown>> {
  const row = (await repository.query(`SELECT t.id, s.housing_ratio, s.energy_ratio, s.connectivity_ratio, s.health_ratio FROM humans h JOIN house_affiliations ha ON ha.house_id = h.house_id AND ha.status = 'ACTIVE' JOIN territories t ON t.corporation_id = ha.corporation_id LEFT JOIN territory_capacity_state s ON s.territory_id = t.id WHERE h.id = $1 ORDER BY t.id LIMIT 1`, [humanId])).rows[0] as any;
  const ratios = { housing: Number(row?.housing_ratio ?? 0), utilities: Number(row?.energy_ratio ?? 0), connectivity: Number(row?.connectivity_ratio ?? 0), health: Number(row?.health_ratio ?? 0) };
  return { territoryId: row?.id ?? null, provider: row ? 'territory-capacity' : null, ratios, status: Object.fromEntries(Object.entries(ratios).map(([key, value]) => [key, value >= 1 ? 'normal' : value >= .75 ? 'basic' : 'critical'])), essentialServicesIndex: Math.min(...Object.values(ratios)) };
}

export async function listPantheonOfAchievements(repository: PostgresRepository): Promise<Record<string, unknown>> { return { deceasedPantheon: [], livingLeaders: [], houses: [], dynasticHouses: [] }; }
export async function listCemeteryProfiles(repository: PostgresRepository, query: { search?: string; house?: string; dynasty?: string; limit?: number }): Promise<Record<string, unknown>> { return { profiles: [] }; }
export async function listMarketPriceHistory(repository: PostgresRepository, product: string, limitDays = 30): Promise<Record<string, unknown>> { return { product, history: [] }; }
