import type { PostgresRepository } from './repository';
import { mapTechnologyCatalogRow } from './technology-postgres.ts';
import { spotInstrumentSymbol } from './market-model.ts';
export { listEvents } from './read-models/events-read.ts';
export { listHistory } from './read-models/events-read.ts';
export { listNotifications, markNotificationRead, markAllNotificationsRead } from './read-models/notifications-read.ts';


export async function auditWorld(repository: PostgresRepository, humanId: string): Promise<Record<string, unknown>> {
  const [balances, ledger, succession, corporations, cities, market] = await Promise.all([
    repository.query<{ invalid: string }>('SELECT COUNT(*)::integer AS invalid FROM economic_accounts WHERE balance_units < 0'),
    repository.query<{ invalid: string }>('SELECT COUNT(*)::integer AS invalid FROM economic_entries WHERE delta_units = 0'),
    repository.query<{ count: string }>('SELECT COUNT(*)::integer AS count FROM succession_plans WHERE human_id = $1', [humanId]),
    repository.query<{ invalid: string }>('SELECT COUNT(*)::integer AS invalid FROM corporations c JOIN corporation_membership_summary s ON s.corporation_id = c.id WHERE c.member_count != s.active_house_count'),
    repository.query<{ invalid: string }>('SELECT COUNT(*)::integer AS invalid FROM cities c JOIN city_population_summary s ON s.city_id = c.id WHERE c.residents != s.active_house_count'),
    repository.query<{ check_name: string; invalid_count: string }>('SELECT check_name, invalid_count FROM earth_market_integrity_report()'),
  ]);
  const marketChecks = Object.fromEntries(market.rows.map((row) => [row.check_name, Number(row.invalid_count) === 0]));
  const checks = { balancesNonNegative: Number(balances.rows[0]?.invalid ?? 0) === 0, ledgerEntriesValid: Number(ledger.rows[0]?.invalid ?? 0) === 0, oneSuccessionPlanPerHuman: Number(succession.rows[0]?.count ?? 0) <= 1, corporationMemberCountsConsistent: Number(corporations.rows[0]?.invalid ?? 0) === 0, cityResidentCountsConsistent: Number(cities.rows[0]?.invalid ?? 0) === 0, market: Object.values(marketChecks).every(Boolean) };
  return { ok: Object.values(checks).every(Boolean), checks };
}

export async function listInstitutions(repository: PostgresRepository): Promise<Record<string, unknown>> {
  const [institutions, cities, corporations, budgets] = await Promise.all([
    repository.query('SELECT id, kind, name, status FROM institutions ORDER BY id'),
    repository.query('SELECT id, corporation_id, status FROM cities ORDER BY id'),
    repository.query('SELECT id, status FROM corporations ORDER BY id'),
    repository.query('SELECT id, institution_id, fiscal_period_id, category_id, authorized_units, committed_units, spent_units, status, rule_version FROM institution_budget_lines ORDER BY id'),
  ]);
  return { institutions: institutions.rows, community: [], city: cities.rows, corporation: corporations.rows, membership: [], budgets: budgets.rows };
}

export interface RankingsQueryOptions {
  category?: string;
  metric?: string;
  search?: string;
  limit?: number;
  offset?: number;
  currentHumanId?: string;
}

export async function listRankings(repository: PostgresRepository, options: RankingsQueryOptions = {}): Promise<Record<string, unknown>> {
  // The clean baseline intentionally has no player/read-model rows. Keep the
  // public projection valid without querying retired pre-baseline columns.
  const empty = { rankings: [], wealth: [], cities: [], corporations: [], technologies: [], generatedFrom: 'planetscale-postgres' };
  if (!options.currentHumanId) return empty;
  const limit = Math.min(100, Math.max(1, options.limit ?? 50));
  const [wealth, cities, corporations, technologies, humans, dynasticHouses] = await Promise.all([
    repository.query<{ human_id: string; balance: string }>(
      `SELECT h.id AS human_id,
              (COALESCE(a.balance_units, 0)
               + COALESCE((SELECT SUM(d.principal_units + d.accrued_interest_units)
                           FROM bank_deposits d
                           WHERE d.depositor_economic_id = o.economic_id
                             AND d.status IN ('ACTIVE', 'MATURED')), 0)
               - COALESCE((SELECT SUM(l.outstanding_principal_units + l.accrued_interest_units)
                           FROM bank_loans l
                           WHERE l.borrower_economic_id = o.economic_id
                             AND l.status IN ('ACTIVE', 'DEFAULTED')), 0))::TEXT AS balance
       FROM humans h
       JOIN houses house ON house.id = h.house_id
       JOIN owner_registry o ON o.id = house.id
       LEFT JOIN economic_accounts a ON a.owner_economic_id = o.economic_id
         AND a.asset_id = 1 AND a.account_type = 'WALLET' AND a.status = 'ACTIVE'
       WHERE h.status = 'ACTIVE'
       ORDER BY (COALESCE(a.balance_units, 0)
                 + COALESCE((SELECT SUM(d.principal_units + d.accrued_interest_units)
                             FROM bank_deposits d
                             WHERE d.depositor_economic_id = o.economic_id
                               AND d.status IN ('ACTIVE', 'MATURED')), 0)
                 - COALESCE((SELECT SUM(l.outstanding_principal_units + l.accrued_interest_units)
                             FROM bank_loans l
                             WHERE l.borrower_economic_id = o.economic_id
                               AND l.status IN ('ACTIVE', 'DEFAULTED')), 0)) DESC, h.id
       LIMIT $1`,
      [limit]
    ),
    repository.query<{ id: string; residents: number; treasury: string; housing_capacity: number; energy_capacity: number; connectivity_capacity: number; health_capacity: number }>(
      `SELECT c.id,
              (SELECT COUNT(*)::integer FROM house_affiliations ha WHERE ha.city_id = c.id AND ha.status = 'ACTIVE') AS residents,
              COALESCE(a.balance_units, 0)::TEXT AS treasury,
              COALESCE((SELECT SUM(be.effect_value) FROM buildings b JOIN building_catalog_effects be ON be.catalog_id = b.catalog_id WHERE b.city_id = c.id AND b.status = 'ACTIVE' AND be.effect_code = 'HOUSING_CAPACITY'), 0)::integer AS housing_capacity,
              COALESCE((SELECT SUM(be.effect_value) FROM buildings b JOIN building_catalog_effects be ON be.catalog_id = b.catalog_id WHERE b.city_id = c.id AND b.status = 'ACTIVE' AND be.effect_code = 'ENERGY_CAPACITY'), 0)::integer AS energy_capacity,
              COALESCE((SELECT SUM(be.effect_value) FROM buildings b JOIN building_catalog_effects be ON be.catalog_id = b.catalog_id WHERE b.city_id = c.id AND b.status = 'ACTIVE' AND be.effect_code = 'CONNECTIVITY_CAPACITY'), 0)::integer AS connectivity_capacity,
              COALESCE((SELECT SUM(be.effect_value) FROM buildings b JOIN building_catalog_effects be ON be.catalog_id = b.catalog_id WHERE b.city_id = c.id AND b.status = 'ACTIVE' AND be.effect_code = 'HEALTH_CAPACITY'), 0)::integer AS health_capacity
       FROM cities c
       JOIN owner_registry o ON o.id = c.id
       LEFT JOIN economic_accounts a ON a.owner_economic_id = o.economic_id
         AND a.asset_id = 1 AND a.account_type = 'TREASURY' AND a.status = 'ACTIVE'
       ORDER BY c.id
       LIMIT $1`,
      [limit]
    ),
    repository.query<{ id: string; member_count: number; treasury: string }>(
      `SELECT c.id, (SELECT COUNT(*)::integer FROM house_affiliations ha WHERE ha.corporation_id = c.id AND ha.status = 'ACTIVE') AS member_count,
              COALESCE(a.balance_units, 0)::TEXT AS treasury
       FROM corporations c
       JOIN owner_registry o ON o.id = c.id
       LEFT JOIN economic_accounts a ON a.owner_economic_id = o.economic_id
         AND a.asset_id = 1 AND a.account_type = 'TREASURY' AND a.status = 'ACTIVE'
       ORDER BY c.id
       LIMIT $1`,
      [limit]
    ),
    repository.query<{ id: string; name: string; owner_id: string; progress: number }>(
      `SELECT p.target_id AS id, tc.name,
          ROUND(p.progress_research_points * 100.0 / NULLIF(p.required_research_points, 0), 2) AS progress
       FROM corporation_research_projects p
       JOIN technology_catalog tc ON tc.id = p.target_id
       WHERE p.target_type = 'TECHNOLOGY'
       ORDER BY progress DESC LIMIT $1`,
      [limit]
    ),
    repository.query<{
      id: string;
      display_name: string;
      age_years: number;
      standing: number;
      legacy: number;
      life_status: string;
      city_id: string | null;
      house_name: string | null;
      dynasty_name?: string | null;
      balance: string;
    }>(`
      SELECT h.id, h.display_name, h.age_years, h.standing, h.final_legacy AS legacy, h.status AS life_status,
             affiliations.city_id, d.house_name, d.house_name AS dynasty_name,
             COALESCE(ab.balance_units, 0) AS balance
      FROM humans h
      LEFT JOIN houses d ON d.current_human_id = h.id
      LEFT JOIN owner_registry o ON o.id = d.id
      LEFT JOIN economic_accounts ab ON ab.owner_economic_id = o.economic_id AND ab.asset_id = 1 AND ab.account_type = 'WALLET' AND ab.status = 'ACTIVE'
      LEFT JOIN LATERAL (SELECT ha.city_id FROM house_affiliations ha WHERE ha.house_id = h.house_id AND ha.status = 'ACTIVE' ORDER BY ha.joined_game_day DESC LIMIT 1) affiliations ON TRUE
      WHERE h.status = 'ACTIVE'
      ORDER BY (h.final_legacy * 3 + h.standing * 2 + FLOOR(COALESCE(ab.balance_units::numeric, 0) / 100)) DESC, h.final_legacy DESC
      LIMIT $1
    `, [limit]).catch(() => ({ rows: [] })),
    repository.query<{
      house_name: string;
      dynasty_name?: string;
      deceased_count: number;
      peak_legacy: number;
      generation: number;
    }>(`
      SELECT h.id AS house_id,
             h.house_name,
             h.house_name AS dynasty_name,
             COUNT(*) FILTER (WHERE human.status = 'DECEASED')::int AS deceased_count,
             h.dynasty_legacy::int AS peak_legacy,
             h.generation::int AS generation
      FROM houses h
      LEFT JOIN humans human ON human.house_id = h.id
      WHERE h.house_name IS NOT NULL AND h.house_name != ''
      GROUP BY h.id, h.house_name, h.dynasty_legacy, h.generation
      ORDER BY h.dynasty_legacy DESC, h.generation DESC, h.id
      LIMIT $1
    `, [limit]).catch(() => ({ rows: [] })),
  ]);

  const totalHumans = humans.rows.length;
  const enrichedHumans = humans.rows.map((h, idx) => {
    const currentRank = idx + 1;
    const rankDelta = 0;
    const isNew = true;
    const percentile = totalHumans > 0 ? (currentRank / totalHumans) * 100 : 100;

    let tierBadge = 'Citizen';
    if (percentile <= 1) tierBadge = 'Sovereign';
    else if (percentile <= 5) tierBadge = 'Patrician';
    else if (percentile <= 20) tierBadge = 'Pioneer';

    const credits = Number(h.balance ?? 0);
    const compositeScore = Number(h.legacy) * 3 + Number(h.standing) * 2 + Math.floor(credits / 100);

    return {
      rank: currentRank,
      rankDelta: isNew ? 'NEW' : rankDelta,
      tierBadge,
      id: h.id,
      displayName: h.display_name,
      ageYears: Number(h.age_years),
      standing: Number(h.standing),
      legacy: Number(h.legacy),
      credits,
      cityId: h.city_id,
      houseName: h.house_name ?? h.dynasty_name ?? null,
      dynastyName: h.house_name ?? h.dynasty_name ?? null,
      compositeScore,
    };
  });

  return {
    ok: true,
    wealth: wealth.rows,
    cities: cities.rows.map((c, idx) => {
      const housingScore = Math.min(1, Number(c.housing_capacity || 0) / Math.max(1, Number(c.residents || 0))) * 25;
      const energyScore = Math.min(1, Number(c.energy_capacity || 0) / Math.max(1, Number(c.residents || 0))) * 25;
      const connectivityScore = Math.min(1, Number(c.connectivity_capacity || 0) / Math.max(1, Number(c.residents || 0))) * 20;
      const healthScore = Math.min(1, Number(c.health_capacity || 0) / 100.0) * 20;
      const treasuryScore = Math.min(1, Math.max(0, Number(c.treasury || 0)) / 10000.0) * 10;
      const compositeIndex = Math.min(100, Math.round(housingScore + energyScore + connectivityScore + healthScore + treasuryScore));
      return {
        rank: idx + 1,
        ...c,
        compositeIndex,
        score: compositeIndex,
        qolIndex: Math.min(100, Math.round(((Number(c.housing_capacity || 0) + Number(c.energy_capacity || 0) + Number(c.health_capacity || 0)) / 300) * 100)),
        rankingFocus: 'services, population, and financial resilience',
      };
    }),
    corporations: corporations.rows.map((corp, idx) => {
      const memberScore = Math.min(1, Math.max(0, Number(corp.member_count || 0)) / 100.0) * 55;
      const treasuryScore = Math.min(1, Math.max(0, Number(corp.treasury || 0)) / 25000.0) * 25;
      const buildingScore = 20;
      const compositeIndex = Math.min(100, Math.round(memberScore + treasuryScore + buildingScore));
      return {
        rank: idx + 1,
        ...corp,
        compositeIndex,
        score: compositeIndex,
        rankingFocus: 'House affiliations, productive buildings, and treasury resilience',
      };
    }),
    technologies: technologies.rows.map((t, idx) => ({
      rank: idx + 1,
      ...t,
    })),
    citizens: enrichedHumans,
    houses: dynasticHouses.rows.map((d, idx) => ({
      rank: idx + 1,
      ...d,
    })),
    dynasticHouses: dynasticHouses.rows.map((d, idx) => ({
      rank: idx + 1,
      ...d,
    })),
    generatedFrom: 'planetscale-postgres',
  };
}

export async function listTechnology(repository: PostgresRepository, humanId: string): Promise<Record<string, unknown>> {
  const [projects, catalog] = await Promise.all([
    repository.query(`SELECT p.* FROM corporation_research_projects p
      JOIN owner_registry o ON o.economic_id = p.corporation_economic_id
      JOIN house_affiliations ha ON ha.corporation_id = o.id
      JOIN humans h ON h.house_id = ha.house_id
      WHERE h.id = $1 AND ha.status = 'ACTIVE' ORDER BY p.id DESC`, [humanId]).catch(() => ({ rows: [] })),
    repository.query(`SELECT tc.id, tc.code, tc.name,
             NULL::text AS category, ''::text AS description,
             tc.patentable, 0::integer AS patent_exclusivity_days,
             tc.credit_cost_units::TEXT AS research_credit_cost_units,
             tc.research_points_required::TEXT, 'ACTIVE'::text AS status,
             tc.definition_version, 1::bigint AS effective_from_game_day,
             NULL::bigint AS effective_to_game_day,
             COALESCE((SELECT jsonb_agg(jsonb_build_object(
               'effectType', e.effect_type, 'targetKey', e.target_key,
               'modifierBps', e.modifier_bps) ORDER BY e.effect_type, e.target_key)
               FROM technology_effects e WHERE e.technology_id = tc.id), '[]'::JSONB) AS effects
        FROM technology_catalog tc ORDER BY tc.code`).catch(() => ({ rows: [] })),
  ]);
  return { catalog: catalog.rows.map(mapTechnologyCatalogRow), projects: projects.rows };
}

export async function listGovernanceProposals(repository: PostgresRepository): Promise<Record<string, unknown>> {
  const [proposals, ballots] = await Promise.all([
    repository.query(`
      SELECT p.*, COALESCE(h.display_name, 'Citizen') AS creator_name
      FROM proposals p
      LEFT JOIN humans h ON h.id = p.created_by_human_id
      ORDER BY p.closes_game_day ASC NULLS LAST, p.closes_game_minute ASC NULLS LAST, p.closes_at ASC
    `),
    repository.query('SELECT proposal_id, choice, ROUND(SUM(weight), 3) AS count FROM ballots GROUP BY proposal_id, choice'),
  ]);
  return { proposals: proposals.rows, voteCounts: ballots.rows };
}

export async function listGovernanceRules(repository: PostgresRepository): Promise<Record<string, unknown>> {
  const rules = await repository.query("SELECT * FROM governance_rules WHERE status IN ('active','superseded') ORDER BY institution_id, category, version DESC");
  return { rules: rules.rows };
}

export async function getServiceStatus(repository: PostgresRepository, humanId: string): Promise<Record<string, unknown>> {
  const city = (await repository.query<Record<string, number>>("SELECT cities.* FROM cities JOIN house_affiliations ha ON ha.city_id = cities.id JOIN humans h ON h.house_id = ha.house_id WHERE h.id = $1 AND ha.status = 'ACTIVE' LIMIT 1", [humanId])).rows[0];
  const independentBaseline = { housing: 0.75, utilities: 0.75, connectivity: 0.75, health: 0.5 };
  const ratios = city ? {
    housing: Math.min(1, Number(city.housing_capacity ?? 0) / Math.max(1, Number(city.residents ?? 0))),
    utilities: Math.min(1, Number(city.energy_capacity ?? 0) / Math.max(1, Number(city.residents ?? 0))),
    connectivity: Math.min(1, Number(city.connectivity_capacity ?? 0) / Math.max(1, Number(city.residents ?? 0))),
    health: Math.min(1, Number(city.health_capacity ?? 0) / 100),
  } : independentBaseline;
  const status = Object.fromEntries(Object.entries(ratios).map(([key, value]) => [key, value >= 1 ? 'normal' : value >= 0.75 ? 'basic' : 'critical']));
  return { cityId: city?.id ?? null, provider: city ? 'city-capacity' : 'ouc-independent-minimum', ratios, status, essentialServicesIndex: Math.min(...Object.values(ratios)) };
}

export async function listPantheonOfAchievements(repository: PostgresRepository): Promise<Record<string, unknown>> {
  const [deceased, active, houses] = await Promise.all([
    repository.query(`
      SELECT h.id AS human_id, h.display_name, h.death_game_day,
             h.age_years AS final_age_years, h.standing AS final_standing,
             h.final_legacy, house.house_name,
             successor.display_name AS successor_name
      FROM humans h
      JOIN houses house ON house.id = h.house_id
      LEFT JOIN succession_events succession ON succession.predecessor_human_id = h.id
      LEFT JOIN humans successor ON successor.id = succession.successor_human_id
      WHERE h.status = 'DECEASED'
      ORDER BY h.final_legacy DESC, h.standing DESC, h.id
      LIMIT 50
    `),
    repository.query(`
      SELECT h.id, h.display_name, h.age_years, h.standing,
             h.final_legacy AS legacy,
             (h.standing * 10 + h.final_legacy * 50 + h.age_years * 2) AS composite_legacy_score
      FROM humans h
      WHERE h.status = 'ACTIVE'
      ORDER BY h.final_legacy DESC, h.standing DESC, h.id
      LIMIT 20
    `),
    repository.query(`
      SELECT house.id AS house_id, house.house_name,
             house.house_name AS dynasty_name,
             COUNT(*) FILTER (WHERE h.status = 'DECEASED')::int AS deceased_count,
             MAX(h.final_legacy)::int AS peak_legacy,
             house.dynasty_legacy, house.generation
      FROM houses house
      LEFT JOIN humans h ON h.house_id = house.id
      WHERE house.house_name IS NOT NULL AND house.house_name != ''
      GROUP BY house.id, house.house_name, house.dynasty_legacy, house.generation
      ORDER BY house.dynasty_legacy DESC, MAX(h.final_legacy) DESC NULLS LAST, house.id
      LIMIT 20
    `),
  ]);
  return {
    deceasedPantheon: deceased.rows,
    livingLeaders: active.rows,
    houses: houses.rows,
    dynasticHouses: houses.rows,
  };
}

export async function listCemeteryProfiles(repository: PostgresRepository, query: { search?: string; house?: string; dynasty?: string; limit?: number }): Promise<Record<string, unknown>> {
  const limit = Math.max(1, Math.min(100, query.limit ?? 50));
  let sql = `
    SELECT h.id AS human_id, h.display_name, h.death_game_day,
           h.age_years AS final_age_years, h.standing AS final_standing,
           h.final_legacy, house.house_name,
           successor.display_name AS successor_name
    FROM humans h
    JOIN houses house ON house.id = h.house_id
    LEFT JOIN succession_events succession ON succession.predecessor_human_id = h.id
    LEFT JOIN humans successor ON successor.id = succession.successor_human_id
    WHERE h.status = 'DECEASED'`;
  const params: unknown[] = [];
  if (query.search && query.search.trim().length > 0) {
    params.push(`%${query.search.trim()}%`);
    sql += ` AND (h.display_name ILIKE $${params.length} OR successor.display_name ILIKE $${params.length} OR house.house_name ILIKE $${params.length})`;
  }
  const houseFilter = query.house?.trim() || query.dynasty?.trim();
  if (houseFilter) {
    params.push(houseFilter);
    sql += ` AND house.house_name = $${params.length}`;
  }
  params.push(limit);
  sql += ` ORDER BY h.death_game_day DESC NULLS LAST, h.final_legacy DESC, h.id LIMIT $${params.length}`;

  const rows = await repository.query(sql, params);
  return {
    cemetery: rows.rows,
    totalReturned: rows.rows.length,
  };
}

export async function listMarketPriceHistory(repository: PostgresRepository, product: string, limitDays = 30): Promise<Record<string, unknown>> {
  const boundedDays = Math.max(1, Math.min(365, limitDays));
  const current = await repository.query<{ price_units: string | null; supply_units: string; demand_units: string }>(
    `SELECT s.last_clearing_price_units AS price_units, s.open_sell_units AS supply_units, s.open_buy_units AS demand_units
       FROM market_instrument_state s
       JOIN market_instruments i ON i.id = s.instrument_id
      WHERE i.symbol = $1`,
    [spotInstrumentSymbol(product)],
  );
  const history = await repository.query<{ game_day: string; price_units: string }>(
    `SELECT period_id AS game_day, close_price_units AS price_units
       FROM market_candles c
       JOIN market_instruments i ON i.id = c.instrument_id
      WHERE i.symbol = $1 AND c.interval_kind = 'daily'
      ORDER BY period_id DESC LIMIT $2`,
    [spotInstrumentSymbol(product), boundedDays],
  );
  return {
    product,
    currentPrice: Number(current.rows[0]?.price_units ?? 1000) / 100,
    supply: Number(current.rows[0]?.supply_units ?? 0) / 1_000_000,
    demand: Number(current.rows[0]?.demand_units ?? 0) / 1_000_000,
    history: history.rows.reverse().map((row) => ({ gameDay: Number(row.game_day), price: Number(row.price_units) / 100 })),
  };
}
