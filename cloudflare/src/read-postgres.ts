import type { PostgresRepository } from './repository';
import { mapTechnologyCatalogRow } from './technology-postgres.ts';
import { spotInstrumentSymbol } from './market-model.ts';

export async function listEvents(repository: PostgresRepository, humanId: string, limit: number): Promise<Record<string, unknown>> {
  const [ledger, trades, proposals, publicNews] = await Promise.all([
    repository.query('SELECT id, created_at AS occurred_at, reason_type AS type, amount, game_day, debit_account AS actor FROM ledger_entries ORDER BY created_at DESC LIMIT $1', [limit]),
    repository.query("SELECT id, created_at AS occurred_at, 'market_trade' AS type, quantity_units AS amount, game_day, instrument_id AS actor FROM market_fills ORDER BY created_at DESC LIMIT $1", [limit]),
    repository.query("SELECT id, opens_at AS occurred_at, 'proposal_opened' AS type, 0 AS amount, EXTRACT(EPOCH FROM opens_at)::integer AS game_day, institution_id AS actor FROM proposals ORDER BY opens_at DESC LIMIT $1", [limit]),
    repository.query("SELECT id, created_at AS occurred_at, event_type, title, details, game_day FROM world_events WHERE event_type NOT IN ('world_clock', 'scheduled_tick') AND LOWER(COALESCE(title, '')) NOT LIKE '%public world announcement%' ORDER BY created_at DESC LIMIT $1", [limit]),
  ]);
  const events = [...ledger.rows, ...trades.rows, ...proposals.rows, ...publicNews.rows]
    .sort((a, b) => String((b as Record<string, unknown>).occurred_at).localeCompare(String((a as Record<string, unknown>).occurred_at)))
    .slice(0, limit);
  return { ok: true, events, generatedAt: new Date().toISOString() };
}

export async function listNotifications(repository: PostgresRepository, humanId: string, limit: number): Promise<Record<string, unknown>> {
  const [notifications, unread] = await Promise.all([
    repository.query('SELECT id, notification_type, title, body, entity_id, read_at, created_at FROM notifications WHERE human_id = $1 ORDER BY created_at DESC LIMIT $2', [humanId, limit]),
    repository.query<{ count: string }>('SELECT COUNT(*)::integer AS count FROM notifications WHERE human_id = $1 AND read_at IS NULL', [humanId]),
  ]);
  return { notifications: notifications.rows, unread: Number(unread.rows[0]?.count ?? 0) };
}

export async function markNotificationRead(repository: PostgresRepository, humanId: string, notificationId: string): Promise<Record<string, unknown>> {
  await repository.query('UPDATE notifications SET read_at = CURRENT_TIMESTAMP WHERE id = $1 AND human_id = $2', [notificationId, humanId]);
  return { ok: true };
}

export async function markAllNotificationsRead(repository: PostgresRepository, humanId: string): Promise<Record<string, unknown>> {
  await repository.query('UPDATE notifications SET read_at = CURRENT_TIMESTAMP WHERE human_id = $1 AND read_at IS NULL', [humanId]);
  return { ok: true, unread: 0, unreadCount: 0 };
}

export async function auditWorld(repository: PostgresRepository, humanId: string): Promise<Record<string, unknown>> {
  const [balances, ledger, succession, corporations, cities, market] = await Promise.all([
    repository.query<{ invalid: string }>('SELECT COUNT(*)::integer AS invalid FROM account_balances WHERE balance < 0'),
    repository.query<{ invalid: string }>('SELECT COUNT(*)::integer AS invalid FROM ledger_entries WHERE amount <= 0 OR debit_account = credit_account'),
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
  const [community, city, corporation, membership, budgets] = await Promise.all([
    repository.query('SELECT * FROM communities ORDER BY id'),
    repository.query('SELECT * FROM cities ORDER BY id'),
    repository.query('SELECT * FROM corporations ORDER BY id'),
    repository.query('SELECT * FROM memberships ORDER BY human_id'),
    repository.query('SELECT b.id, b.institution_id, p.start_game_day AS game_day, p.id AS fiscal_period_id, p.period_type, p.end_game_day, c.category_code, b.authorized_units / 100.0 AS amount, b.authorized_units, b.committed_units, b.spent_units, b.status, b.created_game_day, b.rule_version FROM institution_budget_lines b JOIN fiscal_periods p ON p.id = b.fiscal_period_id JOIN budget_categories c ON c.id = b.category_id ORDER BY p.start_game_day DESC'),
  ]);
  return { community: community.rows, city: city.rows, corporation: corporation.rows, membership: membership.rows, budgets: budgets.rows };
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
  const limit = Math.min(100, Math.max(1, options.limit ?? 50));
  const [wealth, cities, corporations, technologies, humans, dynasticHouses, snapshots] = await Promise.all([
    repository.query<{ human_id: string; balance: string }>(
      "SELECT owner_id AS human_id, balance FROM account_balances WHERE currency = 'CREDIT' ORDER BY balance DESC LIMIT $1",
      [limit]
    ),
    repository.query<{ id: string; residents: number; treasury: string; housing_capacity: number; energy_capacity: number; connectivity_capacity: number; health_capacity: number }>(
      `SELECT c.id, c.residents, COALESCE(a.balance / 100.0, 0)::TEXT AS treasury,
              c.housing_capacity, c.energy_capacity, c.connectivity_capacity, c.health_capacity
       FROM cities c
       JOIN owner_registry o ON o.id = c.id
       LEFT JOIN economic_accounts a ON a.owner_economic_id = o.economic_id
         AND a.asset_id = 1 AND a.account_type = 3 AND a.is_default_settlement AND a.status = 'active'
       ORDER BY (
         LEAST(1, housing_capacity / GREATEST(1, residents::numeric)) * 25
         + LEAST(1, energy_capacity / GREATEST(1, residents::numeric)) * 25
         + LEAST(1, connectivity_capacity / GREATEST(1, residents::numeric)) * 20
         + LEAST(1, health_capacity / 100.0) * 20
         + LEAST(1, GREATEST(0, treasury::numeric) / 10000.0) * 10
       ) DESC, residents DESC, id
       LIMIT $1`,
      [limit]
    ),
    repository.query<{ id: string; member_count: number; treasury: string }>(
      `SELECT c.id, c.member_count, COALESCE(a.balance / 100.0, 0)::TEXT AS treasury
       FROM corporations c
       JOIN owner_registry o ON o.id = c.id
       LEFT JOIN economic_accounts a ON a.owner_economic_id = o.economic_id
         AND a.asset_id = 1 AND a.account_type = 3 AND a.is_default_settlement AND a.status = 'active'
       ORDER BY (LEAST(1, GREATEST(0, member_count::numeric) / 100.0) * 55
                 + LEAST(1, GREATEST(0, treasury::numeric) / 25000.0) * 25
                 + LEAST(1, (SELECT COUNT(*)::numeric FROM buildings b JOIN memberships m ON m.human_id = b.owner_id WHERE m.corporation_id = corporations.id AND b.ownership_class = 'private' AND b.status = 'active') / 10.0) * 20) DESC,
                member_count DESC, id
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
      SELECT h.id, h.display_name, h.age_years, h.standing, h.legacy, h.life_status,
             m.city_id, d.house_name, d.house_name AS dynasty_name,
             COALESCE(ab.balance, '0') AS balance
      FROM humans h
      LEFT JOIN account_balances ab ON ab.account_id = h.account_id AND ab.currency = 'CREDIT'
      LEFT JOIN memberships m ON m.human_id = h.id
      LEFT JOIN houses d ON d.founder_human_id = h.id
      WHERE h.life_status = 'active'
      ORDER BY (h.legacy * 3 + h.standing * 2 + FLOOR(COALESCE(ab.balance::numeric, 0) / 100)) DESC, h.legacy DESC
      LIMIT $1
    `, [limit]).catch(() => ({ rows: [] })),
    repository.query<{
      house_name: string;
      dynasty_name?: string;
      deceased_count: number;
      peak_legacy: number;
      peak_standing: number;
    }>(`
      SELECT dp.house_name AS house_name,
             dp.house_name AS dynasty_name,
             COUNT(*)::int AS deceased_count,
             MAX(dp.final_legacy)::int AS peak_legacy,
             MAX(dp.final_standing)::int AS peak_standing
      FROM deceased_profiles dp
      WHERE dp.house_name IS NOT NULL AND dp.house_name != ''
      GROUP BY dp.house_name
      ORDER BY MAX(dp.final_legacy) DESC, COUNT(*) DESC
      LIMIT $1
    `, [limit]).catch(() => ({ rows: [] })),
    repository.query<{
      ranking_type: string;
      entity_id: string;
      rank: number;
      game_day: number;
    }>(`
      SELECT ranking_type, entity_id, rank, game_day
      FROM rankings_snapshots
      WHERE game_day = (SELECT MAX(game_day) FROM rankings_snapshots)
      LIMIT 200
    `).catch(() => ({ rows: [] })),
  ]);

  const snapshotMap = new Map<string, number>();
  for (const s of snapshots.rows) {
    snapshotMap.set(`${s.ranking_type}:${s.entity_id}`, Number(s.rank));
  }

  const totalHumans = humans.rows.length;
  const enrichedHumans = humans.rows.map((h, idx) => {
    const currentRank = idx + 1;
    const prevRank = snapshotMap.get(`citizens:${h.id}`);
    const rankDelta = prevRank ? prevRank - currentRank : 0;
    const isNew = prevRank === undefined;
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
      const businessScore = 20;
      const compositeIndex = Math.min(100, Math.round(memberScore + treasuryScore + businessScore));
      return {
        rank: idx + 1,
        ...corp,
        compositeIndex,
        score: compositeIndex,
        rankingFocus: 'membership, productive businesses, and treasury resilience',
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

export async function listHistory(repository: PostgresRepository, limit: number): Promise<Record<string, unknown>> {
  const [events, rankings, deceased] = await Promise.all([
    repository.query('SELECT id, game_day, event_type, title, details FROM world_events ORDER BY game_day DESC, created_at DESC LIMIT $1', [limit]),
    repository.query('SELECT game_day, ranking_type, entity_id, rank, score FROM rankings_snapshots ORDER BY game_day DESC, ranking_type, rank LIMIT $1', [limit * 4]),
    repository.query('SELECT human_id, display_name, death_game_day, final_standing, final_legacy, successor_name FROM deceased_profiles ORDER BY death_game_day DESC LIMIT $1', [limit]),
  ]);
  return { events: events.rows, rankings: rankings.rows, deceased: deceased.rows };
}

export async function listOwnershipEvents(repository: PostgresRepository, humanId: string, limit: number): Promise<Record<string, unknown>> {
  const events = await repository.query('SELECT id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day, created_at FROM ownership_events WHERE from_owner_id = $1 OR to_owner_id = $1 ORDER BY game_day DESC, created_at DESC LIMIT $2', [humanId, limit]);
  return { events: events.rows };
}

export async function listMembershipEvents(repository: PostgresRepository, humanId: string, limit: number): Promise<Record<string, unknown>> {
  const events = await repository.query('SELECT id, institution_type, institution_id, action, game_day, reason, created_at FROM membership_events WHERE human_id = $1 ORDER BY game_day DESC, created_at DESC LIMIT $2', [humanId, limit]);
  return { events: events.rows };
}

export async function listTechnology(repository: PostgresRepository, humanId: string): Promise<Record<string, unknown>> {
  const [projects, catalog] = await Promise.all([
    repository.query(`SELECT p.* FROM corporation_research_projects p
      JOIN memberships m ON m.corporation_id = (SELECT source_id FROM owner_registry WHERE economic_id = p.corporation_economic_id)
      WHERE m.human_id = $1 ORDER BY p.created_at DESC`, [humanId]).catch(() => ({ rows: [] })),
    repository.query("SELECT DISTINCT ON (tc.code) tc.id, tc.code, tc.name, tc.category, tc.description, tc.patentable, tc.patent_exclusivity_days, tc.research_credit_cost_units::TEXT, tc.research_points_required::TEXT, tc.status, tc.definition_version, tc.effective_from_game_day, tc.effective_to_game_day, (SELECT COALESCE(jsonb_agg(jsonb_build_object('effectType', e.effect_type, 'modifierFamily', e.modifier_family, 'targetType', e.target_type, 'targetKey', e.target_key, 'modifierBps', e.modifier_bps) ORDER BY e.id), '[]'::JSONB) FROM technology_effects e WHERE e.technology_id = tc.id) AS effects FROM technology_catalog tc WHERE tc.status = 'ACTIVE' AND tc.effective_from_game_day <= COALESCE((SELECT game_day FROM world_state WHERE id = 'WORLD'), 0) AND (tc.effective_to_game_day IS NULL OR tc.effective_to_game_day >= COALESCE((SELECT game_day FROM world_state WHERE id = 'WORLD'), 0)) ORDER BY tc.code, tc.effective_from_game_day DESC, tc.definition_version DESC").catch(() => ({ rows: [] })),
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
  const city = (await repository.query<Record<string, number>>('SELECT cities.* FROM cities JOIN memberships ON memberships.city_id = cities.id WHERE memberships.human_id = $1', [humanId])).rows[0];
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

export async function listProductionEvents(_repository: PostgresRepository, _humanId: string, _limit: number): Promise<Record<string, unknown>> { return { events: [] }; }

export async function readBusiness(repository: PostgresRepository, businessId: string, viewerId: string): Promise<Record<string, unknown>> {
  const business = await repository.query("SELECT businesses.id, businesses.name, businesses.owner_id, businesses.status, COALESCE(business_financials.revenue, 0) AS revenue, COALESCE(business_financials.operating_costs, 0) AS operating_costs, COALESCE(business_financials.profit, 0) AS profit, COALESCE(business_financials.taxed_revenue, 0) AS taxed_revenue, COALESCE(business_financials.last_game_day, 1) AS last_game_day, business_financials.updated_at FROM businesses LEFT JOIN business_financials ON business_financials.business_id = businesses.id LEFT JOIN business_management ON business_management.business_id = businesses.id WHERE businesses.id = $1 AND (businesses.owner_id = $2 OR business_management.manager_id = $2 OR EXISTS (SELECT 1 FROM business_shares WHERE business_shares.business_id = businesses.id AND business_shares.holder_id = $2))", [businessId, viewerId]);
  return business.rows[0] ? { business: business.rows[0] } : { error: 'Business financial statement is not available to this Human' };
}

export async function readBusinessProfile(repository: PostgresRepository, businessId: string, viewerId: string): Promise<Record<string, unknown>> {
  const access = await repository.query<{ id: string; owner_id: string; manager_id: string | null }>(
    'SELECT businesses.id, businesses.owner_id, business_management.manager_id FROM businesses LEFT JOIN business_management ON business_management.business_id = businesses.id WHERE businesses.id = $1 AND (businesses.owner_id = $2 OR business_management.manager_id = $2 OR EXISTS (SELECT 1 FROM business_shares WHERE business_shares.business_id = businesses.id AND business_shares.holder_id = $2))',
    [businessId, viewerId],
  );
  if (!access.rows[0]) return { error: 'Business profile is not available to this Human' };

  const [business, financials, management, constitution, assets, holders] = await Promise.all([
    repository.query('SELECT id, owner_id, name, sector, policy, condition, status FROM businesses WHERE id = $1', [businessId]),
    repository.query('SELECT revenue, operating_costs, profit, taxed_revenue, last_game_day, updated_at FROM business_financials WHERE business_id = $1', [businessId]),
    repository.query('SELECT business_management.manager_id, humans.display_name AS manager_name, business_management.appointed_by, business_management.appointed_game_day, business_management.updated_at FROM business_management JOIN humans ON humans.id = business_management.manager_id WHERE business_management.business_id = $1', [businessId]),
    repository.query('SELECT version, shareholder_vote_threshold, board_approval_threshold, dilution_notice_days, updated_by, updated_game_day, updated_at FROM business_constitutions WHERE business_id = $1', [businessId]),
    repository.query('SELECT id, name, building_type, status FROM buildings WHERE business_id = $1 ORDER BY id', [businessId]),
    repository.query('SELECT business_shares.holder_id, humans.display_name, business_shares.shares FROM business_shares JOIN humans ON humans.id = business_shares.holder_id WHERE business_shares.business_id = $1 ORDER BY business_shares.shares DESC, business_shares.holder_id', [businessId]),
  ]);
  const totalIssuedShares = holders.rows.reduce((total, holder) => total + Number((holder as { shares: unknown }).shares ?? 0), 0);
  return {
    business: business.rows[0] ?? null,
    financials: financials.rows[0] ?? null,
    management: management.rows[0] ?? { manager_id: access.rows[0].manager_id ?? access.rows[0].owner_id, owner_id: access.rows[0].owner_id },
    constitution: constitution.rows[0] ?? null,
    assets: assets.rows,
    ownership: {
      totalIssuedShares,
      holders: holders.rows.map((holder) => ({ ...holder, percentage: totalIssuedShares > 0 ? Math.round(Number((holder as { shares: unknown }).shares ?? 0) / totalIssuedShares * 10000) / 100 : 0 })),
    },
    access: { viewerId, isOwner: access.rows[0].owner_id === viewerId, isManager: access.rows[0].manager_id === viewerId },
  };
}

export async function listPantheonOfAchievements(repository: PostgresRepository): Promise<Record<string, unknown>> {
  const [deceased, active, houses] = await Promise.all([
    repository.query('SELECT * FROM deceased_profiles ORDER BY final_legacy DESC, final_standing DESC LIMIT 50'),
    repository.query("SELECT id, display_name, age_years, standing, legacy, (standing * 10 + legacy * 50 + age_years * 2) AS composite_legacy_score FROM humans WHERE life_status = 'active' ORDER BY legacy DESC, standing DESC LIMIT 20"),
    repository.query("SELECT house_name, house_name as dynasty_name, COUNT(*)::int as deceased_count, MAX(final_legacy)::int as peak_legacy FROM deceased_profiles WHERE house_name IS NOT NULL AND house_name != '' GROUP BY house_name ORDER BY peak_legacy DESC LIMIT 20"),
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
  let sql = 'SELECT * FROM deceased_profiles WHERE 1=1';
  const params: unknown[] = [];
  if (query.search && query.search.trim().length > 0) {
    params.push(`%${query.search.trim()}%`);
    sql += ` AND (display_name ILIKE $${params.length} OR successor_name ILIKE $${params.length} OR house_name ILIKE $${params.length})`;
  }
  const houseFilter = query.house?.trim() || query.dynasty?.trim();
  if (houseFilter) {
    params.push(houseFilter);
    sql += ` AND house_name = $${params.length}`;
  }
  params.push(limit);
  sql += ` ORDER BY death_game_day DESC, final_legacy DESC LIMIT $${params.length}`;

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
      WHERE i.symbol = $1 AND i.instrument_type = 'SPOT'`,
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
