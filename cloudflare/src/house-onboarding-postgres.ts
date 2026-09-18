import type { PostgresRepository } from './repository.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';
import { createGameEvent } from './game-events-postgres.ts';

type Milestone = {
  code: string;
  title: string;
  description: string;
  rewardCredits: string;
  targetCategory: string;
  targetAction: string;
};

type ProgressRow = {
  house_id: string;
  onboarding_version: number;
  status: 'ACTIVE' | 'COMPLETED' | 'SKIPPED';
  completed_milestones: string[];
  completed_game_day: number | null;
};
type QueryRows<Row> = { rows?: Row[] } | undefined;

function rowsOf<Row>(result: QueryRows<Row>): Row[] {
  return result?.rows ?? [];
}

export const ONBOARDING_MILESTONES: Milestone[] = [
  { code: 'EXPLORE_OVERVIEW', title: 'Tour Your House', description: 'Review your initial household wallet balance and food reserves.', rewardCredits: '100', targetCategory: 'OVERVIEW', targetAction: 'review_house_assets' },
  { code: 'INSPECT_TERRITORY', title: 'Inspect Territory', description: 'Check local territory capacity, congestion, and public amenities.', rewardCredits: '100', targetCategory: 'TERRITORY', targetAction: 'inspect_territory' },
  { code: 'SET_HOUSE_POLICY', title: 'Set First House Policy', description: 'Adopt an operating stance for dividend reinvestment and resource consumption.', rewardCredits: '150', targetCategory: 'POLICY', targetAction: 'set_operating_policy' },
  { code: 'PRODUCE_FIRST_OUTPUT', title: 'Activate A Production Facility', description: 'Ensure your house or workplace has an active productive installation.', rewardCredits: '250', targetCategory: 'PRODUCTION', targetAction: 'start_first_producer' },
  { code: 'EXECUTE_FIRST_ORDER', title: 'Participate In The Market', description: 'Submit an order to purchase missing inputs or sell surplus inventory.', rewardCredits: '200', targetCategory: 'MARKET', targetAction: 'place_first_market_order' },
  { code: 'JOIN_ORGANIZATION', title: 'Explore Social Entities', description: 'Inspect available corporations, syndicates, and communities.', rewardCredits: '200', targetCategory: 'ORGANIZATIONS', targetAction: 'discover_organization' },
];

const ACTION_ROUTES: Record<string, string> = {
  review_house_assets: '/app/house',
  inspect_territory: '/app/territory',
  set_operating_policy: '/app/house/policy',
  start_first_producer: '/app/operations',
  place_first_market_order: '/app/market',
  discover_organization: '/app/organizations',
};

function nextMilestone(completed: Set<string>): Milestone | null {
  return ONBOARDING_MILESTONES.find((milestone) => !completed.has(milestone.code)) ?? null;
}

export async function getHouseOnboarding(repository: PostgresRepository, houseId: string): Promise<Record<string, unknown>> {
  const [progress, clock, assets, credit, buildings, orders, residence, territory] = await Promise.all([
    repository.query<ProgressRow>('SELECT house_id, onboarding_version, status, completed_milestones, completed_game_day FROM house_onboarding_progress WHERE house_id = $1', [houseId]),
    readAuthoritativeGameTime(repository),
    repository.query<{ code: string; balance_units: string }>(`SELECT asset.code, COALESCE(account.balance_units, 0)::TEXT AS balance_units
      FROM economic_assets asset LEFT JOIN owner_registry owner ON owner.id = $1 AND owner.owner_type = 'HOUSE'
      LEFT JOIN economic_accounts account ON account.owner_economic_id = owner.economic_id AND account.asset_id = asset.id AND account.account_type = 'INVENTORY' AND account.status = 'ACTIVE'
      WHERE asset.asset_kind = 'RESOURCE' ORDER BY asset.id`, [houseId]),
    repository.query<{ balance_units: string }>(`SELECT COALESCE(account.balance_units, 0)::TEXT AS balance_units
      FROM economic_assets asset LEFT JOIN owner_registry owner ON owner.id = $1 AND owner.owner_type = 'HOUSE'
      LEFT JOIN economic_accounts account ON account.owner_economic_id = owner.economic_id AND account.asset_id = asset.id AND account.account_type = 'WALLET' AND account.status = 'ACTIVE'
      WHERE asset.code = 'CREDIT'`, [houseId]),
    repository.query<{ count: string }>(`SELECT COUNT(*)::TEXT AS count FROM buildings WHERE owner_economic_id = (SELECT economic_id FROM owner_registry WHERE id = $1) AND status IN ('ACTIVE','UNDER_CONSTRUCTION')`, [houseId]),
    repository.query<{ count: string }>(`SELECT COUNT(*)::TEXT AS count FROM market_orders WHERE owner_economic_id = (SELECT economic_id FROM owner_registry WHERE id = $1)`, [houseId]),
    repository.query<{ territory_id: string; territory_name: string; active_house_count: string; house_capacity: string }>(`SELECT r.territory_id, t.name AS territory_name,
             COALESCE(capacity.active_house_count, 0)::TEXT AS active_house_count,
             COALESCE(capacity.house_capacity, 0)::TEXT AS house_capacity
        FROM house_residencies r
        JOIN territories t ON t.id = r.territory_id
        LEFT JOIN LATERAL (
          SELECT active_house_count, house_capacity
            FROM territory_capacity_state
           WHERE territory_id = r.territory_id
           ORDER BY game_day DESC
           LIMIT 1
        ) capacity ON TRUE
       WHERE r.house_id = $1 AND r.residency_class = 'PRIMARY' AND r.status = 'ACTIVE'
       ORDER BY r.effective_from_game_day DESC LIMIT 1`, [houseId]),
  ]);
  const progressRows = rowsOf(progress);
  const assetRows = rowsOf(assets);
  const creditRows = rowsOf(credit);
  const buildingRows = rowsOf(buildings);
  const orderRows = rowsOf(orders);
  const territoryRows = rowsOf(territory);
  const row = progressRows[0] ?? { house_id: houseId, onboarding_version: 1, status: 'ACTIVE', completed_milestones: [], completed_game_day: null };
  const completed = new Set(Array.isArray(row.completed_milestones) ? row.completed_milestones : []);
  const next = nextMilestone(completed);
  const residenceRow = territoryRows[0];
  const capacityAvailable = residenceRow
    ? Math.max(0, Number(residenceRow.house_capacity) - Number(residenceRow.active_house_count))
    : null;
  const recommendation = next
    ? {
        milestone: next.code,
        actionRoute: ACTION_ROUTES[next.code],
        reason: next.code === 'inspect_territory' && capacityAvailable !== null
          ? `${residenceRow.territory_name} has ${capacityAvailable} reported House slot${capacityAvailable === 1 ? '' : 's'} available.`
          : next.description,
      }
    : null;
  return {
    status: row.status, version: row.onboarding_version,
    currentGameDay: clock.gameDay, completedMilestones: [...completed],
    milestones: ONBOARDING_MILESTONES, recommendedNext: next, recommendation,
    facts: {
      creditBalanceUnits: creditRows[0]?.balance_units ?? '0',
      resourceBalances: assetRows,
      buildingCount: Number(buildingRows[0]?.count ?? 0),
      marketOrderCount: Number(orderRows[0]?.count ?? 0),
      residence: residenceRow ? {
        territoryId: residenceRow.territory_id,
        territoryName: residenceRow.territory_name,
        activeHouseCount: Number(residenceRow.active_house_count),
        houseCapacity: Number(residenceRow.house_capacity),
        capacityAvailable,
      } : null,
    },
    generatedFrom: 'postgres-canonical-facts',
  };
}

export async function advanceHouseOnboarding(repository: PostgresRepository, houseId: string, milestone: string | undefined, expertSkip: boolean, correlationId: string): Promise<Record<string, unknown>> {
  if (!expertSkip && !ONBOARDING_MILESTONES.some((item) => item.code === milestone)) throw new Error('Unknown onboarding milestone');
  return repository.transaction(async (tx) => {
    const replay = await tx.query('SELECT 1 FROM game_events WHERE correlation_id = $1 LIMIT 1', [correlationId]);
    if (replay.rows[0]) return { ok: true, alreadyProcessed: true, correlationId };
    const gameDay = (await readAuthoritativeGameTime(tx)).gameDay;
    const current = (await tx.query<ProgressRow>('SELECT house_id, onboarding_version, status, completed_milestones, completed_game_day FROM house_onboarding_progress WHERE house_id = $1 FOR UPDATE', [houseId])).rows[0];
    if (!current) throw new Error('House onboarding state is unavailable');
    if (current.status !== 'ACTIVE') return { ok: true, alreadyProcessed: true, status: current.status, completedMilestones: current.completed_milestones };
    const completed = new Set(Array.isArray(current.completed_milestones) ? current.completed_milestones : []);
    let status: 'ACTIVE' | 'COMPLETED' | 'SKIPPED' = 'ACTIVE';
    if (expertSkip) status = 'SKIPPED';
    else if (!completed.has(milestone!)) completed.add(milestone!);
    if (!expertSkip && completed.size === ONBOARDING_MILESTONES.length) status = 'COMPLETED';
    await tx.query('UPDATE house_onboarding_progress SET status = $2, completed_milestones = $3::JSONB, completed_game_day = CASE WHEN $2 <> \'ACTIVE\' THEN $4 ELSE completed_game_day END, updated_at = CURRENT_TIMESTAMP WHERE house_id = $1', [houseId, status, JSON.stringify([...completed]), gameDay]);
    await createGameEvent(tx, {
      id: `onboarding:${houseId}:${correlationId}`,
      category: 'IDENTITY', eventType: 'ONBOARDING_PROGRESSED', gameDay,
      subjectType: 'HOUSE', subjectId: houseId,
      title: 'House onboarding progressed', details: { milestone: milestone ?? null, expertSkip },
      correlationId,
    });
    return { ok: true, status, completedMilestones: [...completed], gameDay, correlationId };
  });
}
