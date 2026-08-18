import type { PostgresRepository } from './repository';

export async function listEvents(repository: PostgresRepository, humanId: string, limit: number): Promise<Record<string, unknown>> {
  const [ledger, trades, maintenance, production, proposals] = await Promise.all([
    repository.query('SELECT id, created_at AS occurred_at, reason_type AS type, amount, game_day, debit_account AS actor FROM ledger_entries ORDER BY created_at DESC LIMIT $1', [limit]),
    repository.query("SELECT id, created_at AS occurred_at, 'market_trade' AS type, quantity AS amount, game_day, product AS actor FROM market_trades ORDER BY created_at DESC LIMIT $1", [limit]),
    repository.query("SELECT id, created_at AS occurred_at, 'machine_maintenance' AS type, amount, game_day, machine_id AS actor FROM maintenance_events WHERE owner_id = $1 ORDER BY created_at DESC LIMIT $2", [humanId, limit]),
    repository.query("SELECT id, created_at AS occurred_at, 'machine_production' AS type, amount, game_day, machine_id AS actor FROM production_events WHERE owner_id = $1 ORDER BY created_at DESC LIMIT $2", [humanId, limit]),
    repository.query("SELECT id, opens_at AS occurred_at, 'proposal_opened' AS type, 0 AS amount, EXTRACT(EPOCH FROM opens_at)::integer AS game_day, institution_id AS actor FROM proposals ORDER BY opens_at DESC LIMIT $1", [limit]),
  ]);
  const events = [...ledger.rows, ...trades.rows, ...maintenance.rows, ...production.rows, ...proposals.rows]
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

export async function auditWorld(repository: PostgresRepository, humanId: string): Promise<Record<string, unknown>> {
  const [balances, ledger, machines, succession, corporations, cities] = await Promise.all([
    repository.query<{ invalid: string }>('SELECT COUNT(*)::integer AS invalid FROM account_balances WHERE balance < 0'),
    repository.query<{ invalid: string }>('SELECT COUNT(*)::integer AS invalid FROM ledger_entries WHERE amount <= 0 OR debit_account = credit_account'),
    repository.query<{ invalid: string }>('SELECT COUNT(*)::integer AS invalid FROM machines WHERE condition < 0 OR condition > 100'),
    repository.query<{ count: string }>('SELECT COUNT(*)::integer AS count FROM succession_plans WHERE human_id = $1', [humanId]),
    repository.query<{ invalid: string }>('SELECT COUNT(*)::integer AS invalid FROM corporations WHERE member_count != (SELECT COUNT(*) FROM memberships WHERE memberships.corporation_id = corporations.id)'),
    repository.query<{ invalid: string }>('SELECT COUNT(*)::integer AS invalid FROM cities WHERE residents != (SELECT COUNT(*) FROM memberships WHERE memberships.city_id = cities.id)'),
  ]);
  const checks = { balancesNonNegative: Number(balances.rows[0]?.invalid ?? 0) === 0, ledgerEntriesValid: Number(ledger.rows[0]?.invalid ?? 0) === 0, machineConditionsBounded: Number(machines.rows[0]?.invalid ?? 0) === 0, oneSuccessionPlanPerHuman: Number(succession.rows[0]?.count ?? 0) <= 1, corporationMemberCountsConsistent: Number(corporations.rows[0]?.invalid ?? 0) === 0, cityResidentCountsConsistent: Number(cities.rows[0]?.invalid ?? 0) === 0 };
  return { ok: Object.values(checks).every(Boolean), checks };
}

export async function listInstitutions(repository: PostgresRepository): Promise<Record<string, unknown>> {
  const [community, city, corporation, membership, budgets] = await Promise.all([
    repository.query('SELECT * FROM communities ORDER BY id'),
    repository.query('SELECT * FROM cities ORDER BY id'),
    repository.query('SELECT * FROM corporations ORDER BY id'),
    repository.query('SELECT * FROM memberships ORDER BY human_id'),
    repository.query('SELECT * FROM budgets ORDER BY game_day DESC'),
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
      'SELECT id, residents, treasury, housing_capacity, energy_capacity, connectivity_capacity, health_capacity FROM cities ORDER BY treasury DESC LIMIT $1',
      [limit]
    ),
    repository.query<{ id: string; member_count: number; treasury: string }>(
      'SELECT id, member_count, treasury FROM corporations ORDER BY member_count DESC, treasury DESC LIMIT $1',
      [limit]
    ),
    repository.query<{ id: string; name: string; owner_id: string; progress: number }>(
      'SELECT id, name, owner_id, progress FROM technologies ORDER BY progress DESC LIMIT $1',
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
      dynasty_name: string | null;
      balance: string;
    }>(`
      SELECT h.id, h.display_name, h.age_years, h.standing, h.legacy, h.life_status,
             h.city_id, h.dynasty_name,
             COALESCE(ab.balance, '0') AS balance
      FROM humans h
      LEFT JOIN account_balances ab ON ab.account_id = h.account_id AND ab.currency = 'CREDIT'
      WHERE h.life_status = 'active'
      ORDER BY (h.legacy * 3 + h.standing * 2 + FLOOR(COALESCE(ab.balance::numeric, 0) / 100)) DESC, h.legacy DESC
      LIMIT $1
    `, [limit]).catch(() => ({ rows: [] })),
    repository.query<{
      dynasty_name: string;
      deceased_count: number;
      peak_legacy: number;
      peak_standing: number;
    }>(`
      SELECT dp.dynasty_name,
             COUNT(*)::int AS deceased_count,
             MAX(dp.final_legacy)::int AS peak_legacy,
             MAX(dp.final_standing)::int AS peak_standing
      FROM deceased_profiles dp
      WHERE dp.dynasty_name IS NOT NULL AND dp.dynasty_name != ''
      GROUP BY dp.dynasty_name
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
      dynastyName: h.dynasty_name,
      compositeScore,
    };
  });

  return {
    ok: true,
    wealth: wealth.rows,
    cities: cities.rows.map((c, idx) => ({
      rank: idx + 1,
      ...c,
      qolIndex: Math.min(100, Math.round(((Number(c.housing_capacity || 0) + Number(c.energy_capacity || 0) + Number(c.health_capacity || 0)) / 300) * 100)),
    })),
    corporations: corporations.rows.map((corp, idx) => ({
      rank: idx + 1,
      ...corp,
    })),
    technologies: technologies.rows.map((t, idx) => ({
      rank: idx + 1,
      ...t,
    })),
    citizens: enrichedHumans,
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

export async function listAuthorityEvents(repository: PostgresRepository, humanId: string, limit: number): Promise<Record<string, unknown>> {
  const events = await repository.query('SELECT id, institution_id, role_id, action, game_day, reason, created_at FROM authority_events WHERE human_id = $1 ORDER BY game_day DESC, created_at DESC LIMIT $2', [humanId, limit]);
  return { events: events.rows };
}

export async function listTechnology(repository: PostgresRepository): Promise<Record<string, unknown>> {
  const [projects, patents, licenses] = await Promise.all([
    repository.query('SELECT * FROM research_projects ORDER BY id'),
    repository.query('SELECT * FROM patents ORDER BY id'),
    repository.query('SELECT * FROM technology_licenses ORDER BY id'),
  ]);
  return { projects: projects.rows, patents: patents.rows, licenses: licenses.rows };
}

export async function listGovernanceProposals(repository: PostgresRepository): Promise<Record<string, unknown>> {
  const [proposals, ballots] = await Promise.all([
    repository.query('SELECT * FROM proposals ORDER BY closes_game_day ASC NULLS LAST, closes_game_minute ASC NULLS LAST, closes_at ASC'),
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

export async function listProductionEvents(repository: PostgresRepository, humanId: string, limit: number): Promise<Record<string, unknown>> {
  const events = await repository.query('SELECT production_events.*, machines.name AS machine_name FROM production_events JOIN machines ON machines.id = production_events.machine_id WHERE production_events.owner_id = $1 ORDER BY production_events.game_day DESC, production_events.created_at DESC LIMIT $2', [humanId, limit]);
  return { events: events.rows };
}

export async function readBusiness(repository: PostgresRepository, businessId: string, viewerId: string): Promise<Record<string, unknown>> {
  const business = await repository.query("SELECT businesses.id, businesses.name, businesses.owner_id, businesses.status, business_financials.revenue, business_financials.operating_costs, business_financials.profit, business_financials.taxed_revenue, business_financials.last_game_day, business_financials.updated_at FROM businesses JOIN business_financials ON business_financials.business_id = businesses.id LEFT JOIN business_management ON business_management.business_id = businesses.id WHERE businesses.id = $1 AND (businesses.owner_id = $2 OR business_management.manager_id = $2 OR EXISTS (SELECT 1 FROM business_shares WHERE business_shares.business_id = businesses.id AND business_shares.holder_id = $2))", [businessId, viewerId]);
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
    repository.query('SELECT business_assets.machine_id, machines.name, machines.machine_type, machines.condition, machines.utilization, business_assets.assigned_game_day, business_assets.assigned_by FROM business_assets JOIN machines ON machines.id = business_assets.machine_id WHERE business_assets.business_id = $1 ORDER BY business_assets.machine_id', [businessId]),
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
  const [deceased, active, dynasties] = await Promise.all([
    repository.query('SELECT * FROM deceased_profiles ORDER BY final_legacy DESC, final_standing DESC LIMIT 50'),
    repository.query("SELECT id, display_name, age_years, standing, legacy, (standing * 10 + legacy * 50 + age_years * 2) AS composite_legacy_score FROM humans WHERE life_status = 'active' ORDER BY legacy DESC, standing DESC LIMIT 20"),
    repository.query("SELECT dynasty_name, COUNT(*) as deceased_count, MAX(final_legacy) as peak_legacy FROM deceased_profiles GROUP BY dynasty_name ORDER BY peak_legacy DESC LIMIT 20"),
  ]);
  return {
    deceasedPantheon: deceased.rows,
    livingLeaders: active.rows,
    dynasticHouses: dynasties.rows,
  };
}

export async function listCemeteryProfiles(repository: PostgresRepository, query: { search?: string; dynasty?: string; limit?: number }): Promise<Record<string, unknown>> {
  const limit = Math.max(1, Math.min(100, query.limit ?? 50));
  let sql = 'SELECT * FROM deceased_profiles WHERE 1=1';
  const params: unknown[] = [];
  if (query.search && query.search.trim().length > 0) {
    params.push(`%${query.search.trim()}%`);
    sql += ` AND (display_name ILIKE $${params.length} OR successor_name ILIKE $${params.length} OR dynasty_name ILIKE $${params.length})`;
  }
  if (query.dynasty && query.dynasty.trim().length > 0) {
    params.push(query.dynasty.trim());
    sql += ` AND dynasty_name = $${params.length}`;
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
  const current = await repository.query<{ price: string; supply: string; demand: string }>('SELECT price, supply, demand FROM market_prices WHERE product = $1', [product]);
  const history = await repository.query<{ game_day: number; score: string }>('SELECT game_day, score AS price FROM rankings_snapshots WHERE ranking_type = $1 ORDER BY game_day DESC LIMIT $2', [`market_price_${product}`, boundedDays]);
  return {
    product,
    currentPrice: Number(current.rows[0]?.price ?? 1),
    supply: Number(current.rows[0]?.supply ?? 0),
    demand: Number(current.rows[0]?.demand ?? 0),
    history: history.rows.map((row) => ({ gameDay: Number(row.game_day), price: Number(row.price) })),
  };
}
