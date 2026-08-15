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

export async function listRankings(repository: PostgresRepository): Promise<Record<string, unknown>> {
  const [wealth, cities, corporations, technologies] = await Promise.all([
    repository.query("SELECT owner_id AS human_id, balance FROM account_balances WHERE currency = 'CREDIT' ORDER BY balance DESC"),
    repository.query('SELECT id, residents, treasury, housing_capacity, energy_capacity, connectivity_capacity, health_capacity FROM cities ORDER BY treasury DESC'),
    repository.query('SELECT id, member_count, treasury FROM corporations ORDER BY member_count DESC, treasury DESC'),
    repository.query('SELECT id, name, owner_id, progress FROM technologies ORDER BY progress DESC'),
  ]);
  return { wealth: wealth.rows, cities: cities.rows, corporations: corporations.rows, technologies: technologies.rows, generatedFrom: 'planetscale-postgres' };
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

export async function readBusiness(repository: PostgresRepository, businessId: string, viewerId: string): Promise<Record<string, unknown>> {
  const business = await repository.query("SELECT businesses.id, businesses.name, businesses.owner_id, businesses.status, business_financials.revenue, business_financials.operating_costs, business_financials.profit, business_financials.taxed_revenue, business_financials.last_game_day, business_financials.updated_at FROM businesses JOIN business_financials ON business_financials.business_id = businesses.id LEFT JOIN business_management ON business_management.business_id = businesses.id WHERE businesses.id = $1 AND (businesses.owner_id = $2 OR business_management.manager_id = $2 OR EXISTS (SELECT 1 FROM business_shares WHERE business_shares.business_id = businesses.id AND business_shares.holder_id = $2))", [businessId, viewerId]);
  return business.rows[0] ? { business: business.rows[0] } : { error: 'Business financial statement is not available to this Human' };
}
