import type { PostgresRepository } from './repository.ts';
import { createGameEvent } from './game-events-postgres.ts';
import { ENTRY_SUPPORT_RULES, evaluateEntrySupportEligibility } from './catch-up.ts';

type SupportRow = { house_id: string; status: string; entry_game_day: string | null; eligible_until_game_day: string | null; claimed_game_day: string | null; correlation_id: string | null };

async function facts(repository: PostgresRepository, houseId: string) {
  const [world, progress, house, buildings, orders, affiliations, support] = await Promise.all([
    repository.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'"),
    repository.query<{ status: string }>('SELECT status FROM house_onboarding_progress WHERE house_id = $1', [houseId]),
    repository.query<{ created_game_day: string | null }>('SELECT NULL::BIGINT AS created_game_day FROM houses WHERE id = $1', [houseId]),
    repository.query<{ count: string }>("SELECT COUNT(*)::TEXT AS count FROM buildings WHERE owner_economic_id = (SELECT economic_id FROM owner_registry WHERE id = $1) AND status IN ('ACTIVE','UNDER_CONSTRUCTION')", [houseId]),
    repository.query<{ count: string }>("SELECT COUNT(*)::TEXT AS count FROM market_orders WHERE owner_economic_id = (SELECT economic_id FROM owner_registry WHERE id = $1) AND status IN ('OPEN','PARTIAL')", [houseId]),
    repository.query<{ count: string }>("SELECT COUNT(*)::TEXT AS count FROM organization_memberships WHERE house_id = $1 AND status = 'ACTIVE'", [houseId]),
    repository.query<SupportRow>('SELECT house_id, status, entry_game_day::TEXT, eligible_until_game_day::TEXT, claimed_game_day::TEXT, correlation_id FROM house_entry_support WHERE house_id = $1', [houseId]),
  ]);
  const day = Number(world.rows[0]?.game_day ?? 1);
  const supportRow = support.rows[0] ?? { house_id: houseId, status: 'INELIGIBLE', entry_game_day: null, eligible_until_game_day: null, claimed_game_day: null, correlation_id: null };
  const entry = evaluateEntrySupportEligibility({
    onboardingStatus: progress.rows[0]?.status ?? 'ACTIVE', currentGameDay: day, entryGameDay: supportRow.entry_game_day == null ? null : Number(supportRow.entry_game_day),
    eligibleUntilGameDay: supportRow.eligible_until_game_day == null ? null : Number(supportRow.eligible_until_game_day),
    buildingCount: Number(buildings.rows[0]?.count ?? 0), marketOrderCount: Number(orders.rows[0]?.count ?? 0), affiliationCount: Number(affiliations.rows[0]?.count ?? 0), supportStatus: supportRow.status,
  });
  return { day, supportRow, entry, counts: { buildings: Number(buildings.rows[0]?.count ?? 0), marketOrders: Number(orders.rows[0]?.count ?? 0), affiliations: Number(affiliations.rows[0]?.count ?? 0) } };
}

export async function getHouseEntrySupport(repository: PostgresRepository, houseId: string) {
  const current = await facts(repository, houseId);
  const opportunities = await repository.query(`
    SELECT 'territory:' || t.id AS id, 'territory' AS kind, t.name AS title,
           'Open capacity: ' || GREATEST(0, COALESCE(s.house_capacity, 0) - COALESCE(s.active_house_count, 0))::TEXT AS detail,
           GREATEST(0, COALESCE(s.house_capacity, 0) - COALESCE(s.active_house_count, 0))::TEXT AS capacity
      FROM territories t LEFT JOIN territory_capacity_state s ON s.territory_id = t.id
     WHERE t.status = 'ACTIVE' AND COALESCE(s.house_capacity, 0) > COALESCE(s.active_house_count, 0)
     ORDER BY (COALESCE(s.house_capacity, 0) - COALESCE(s.active_house_count, 0)) DESC, t.id LIMIT 5`);
  const organizations = await repository.query(`
    SELECT o.id, o.name, o.archetype, o.join_policy,
           COUNT(m.id)::TEXT AS member_count
      FROM organizations o LEFT JOIN organization_memberships m ON m.organization_id = o.id AND m.status = 'ACTIVE'
     WHERE o.status = 'ACTIVE' AND o.join_policy IN ('OPEN','REQUEST')
     GROUP BY o.id, o.name, o.archetype, o.join_policy ORDER BY member_count::INTEGER ASC, o.id LIMIT 5`);
  const markets = await repository.query(`
    SELECT i.symbol, i.asset_id, COUNT(o.id)::TEXT AS open_orders,
           MAX(o.limit_price_units)::TEXT AS top_price
      FROM market_instruments i JOIN market_orders o ON o.instrument_id = i.id
     WHERE i.status = 'ACTIVE' AND o.status IN ('OPEN','PARTIAL')
     GROUP BY i.symbol, i.asset_id ORDER BY COUNT(o.id) DESC, i.symbol LIMIT 5`);
  return {
    ok: true, rulesVersion: ENTRY_SUPPORT_RULES.version, currentGameDay: current.day,
    entrySupport: { ...current.entry, status: current.supportRow.status, bundleDisplayUnits: ENTRY_SUPPORT_RULES.resourceBundleDisplayUnits, creditUnits: ENTRY_SUPPORT_RULES.creditUnits },
    opportunities: { territories: opportunities.rows, organizations: organizations.rows, markets: markets.rows },
    antiSnowball: { frontierTechnologyFree: false, universalWealthEqualization: false, veteranLegacyPreserved: true },
  };
}

export async function claimHouseEntrySupport(repository: PostgresRepository, houseId: string, correlationId: string) {
  return repository.transaction(async (tx) => {
    const replay = await tx.query<{ status: string; claimed_game_day: string | null }>('SELECT status, claimed_game_day::TEXT FROM house_entry_support WHERE correlation_id = $1', [correlationId]);
    if (replay.rows[0]) return { ok: true, alreadyProcessed: true, status: replay.rows[0].status, claimedGameDay: Number(replay.rows[0].claimed_game_day) };
    const row = (await tx.query<SupportRow>('SELECT house_id, status, entry_game_day, eligible_until_game_day, claimed_game_day, correlation_id FROM house_entry_support WHERE house_id = $1 FOR UPDATE', [houseId])).rows[0];
    if (!row || row.status !== 'ELIGIBLE') throw new Error('Entry support has already been claimed');
    const current = await facts(tx, houseId);
    if (!current.entry.eligible) throw new Error('House is not eligible for entry support');
    const economic = (await tx.query<{ economic_id: string }>('SELECT economic_id FROM owner_registry WHERE id = $1 AND owner_type = \'HOUSE\'', [houseId])).rows[0];
    if (!economic) throw new Error('House economy is unavailable');
    const assets = await tx.query<{ id: number; code: string; unit_scale: string }>("SELECT id, code, unit_scale::TEXT FROM economic_assets WHERE code = ANY($1)", [Object.keys(ENTRY_SUPPORT_RULES.resourceBundleDisplayUnits)]);
    const transactions: number[] = [];
    for (const asset of assets.rows) {
      const display = ENTRY_SUPPORT_RULES.resourceBundleDisplayUnits[asset.code as keyof typeof ENTRY_SUPPORT_RULES.resourceBundleDisplayUnits];
      const result = await tx.query<{ earth_issue_starter_package: string }>('SELECT earth_issue_starter_package($1,$2,$3,$4,$5)', [`entry-support:${houseId}:${asset.code}:${correlationId}`, current.day, economic.economic_id, asset.id, BigInt(display) * BigInt(asset.unit_scale)]);
      transactions.push(Number(result.rows[0]?.earth_issue_starter_package));
    }
    await tx.query('UPDATE house_entry_support SET status = \'CLAIMED\', claimed_game_day = $2, claimed_transaction_ids = $3, correlation_id = $4, updated_at = CURRENT_TIMESTAMP WHERE house_id = $1', [houseId, current.day, transactions, correlationId]);
    await createGameEvent(tx, { id: `entry-support:${houseId}:${correlationId}`, category: 'IDENTITY', eventType: 'ENTRY_SUPPORT_CLAIMED', gameDay: current.day, subjectType: 'HOUSE', subjectId: houseId, title: 'Late-entry resource support claimed', details: { transactions, creditUnits: 0, rulesVersion: ENTRY_SUPPORT_RULES.version }, correlationId });
    return { ok: true, status: 'CLAIMED', claimedGameDay: current.day, transactionIds: transactions, bundleDisplayUnits: ENTRY_SUPPORT_RULES.resourceBundleDisplayUnits, creditUnits: 0, correlationId };
  });
}
