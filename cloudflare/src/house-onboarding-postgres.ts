import type { PostgresRepository } from './repository.ts';
import { createGameEvent } from './game-events-postgres.ts';

export const ONBOARDING_MILESTONES = [
  { code: 'review_house_assets', title: 'Review your House assets', description: 'Understand your starting Credit, Food, Energy, and Materials.' },
  { code: 'inspect_territory', title: 'Inspect your Territory', description: 'Choose where your House will build and which capacity constraints matter.' },
  { code: 'set_operating_policy', title: 'Set an operating policy', description: 'Protect reserves and define how your House participates in the Spot Market.' },
  { code: 'start_first_producer', title: 'Start your first producer', description: 'Use a valid server quote to begin a sustainable production loop.' },
  { code: 'place_first_market_order', title: 'Place your first market order', description: 'Buy or sell through the canonical Spot Market with escrow protection.' },
  { code: 'discover_organization', title: 'Discover an Organization', description: 'Find a Corporation or Community that matches your House strategy.' },
] as const;

type ProgressRow = { house_id: string; onboarding_version: string; status: 'ACTIVE' | 'COMPLETED' | 'SKIPPED'; completed_milestones: string[]; completed_game_day: string | null };

function nextMilestone(completed: Set<string>): typeof ONBOARDING_MILESTONES[number] | null {
  return ONBOARDING_MILESTONES.find((milestone) => !completed.has(milestone.code)) ?? null;
}

export async function getHouseOnboarding(repository: PostgresRepository, houseId: string): Promise<Record<string, unknown>> {
  const [progress, world, assets, buildings, orders] = await Promise.all([
    repository.query<ProgressRow>('SELECT house_id, onboarding_version, status, completed_milestones, completed_game_day FROM house_onboarding_progress WHERE house_id = $1', [houseId]),
    repository.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'"),
    repository.query<{ code: string; balance_units: string }>(`SELECT asset.code, COALESCE(account.balance_units, 0)::TEXT AS balance_units
      FROM economic_assets asset LEFT JOIN owner_registry owner ON owner.id = $1 AND owner.owner_type = 'HOUSE'
      LEFT JOIN economic_accounts account ON account.owner_economic_id = owner.economic_id AND account.asset_id = asset.id AND account.account_type = 'INVENTORY' AND account.status = 'ACTIVE'
      WHERE asset.asset_kind = 'RESOURCE' ORDER BY asset.id`, [houseId]),
    repository.query<{ count: string }>(`SELECT COUNT(*)::TEXT AS count FROM buildings WHERE owner_economic_id = (SELECT economic_id FROM owner_registry WHERE id = $1) AND status IN ('ACTIVE','UNDER_CONSTRUCTION')`, [houseId]),
    repository.query<{ count: string }>(`SELECT COUNT(*)::TEXT AS count FROM market_orders WHERE owner_economic_id = (SELECT economic_id FROM owner_registry WHERE id = $1)`, [houseId]),
  ]);
  const row = progress.rows[0] ?? { house_id: houseId, onboarding_version: 'onboarding-v4-1', status: 'ACTIVE', completed_milestones: [], completed_game_day: null };
  const completed = new Set(Array.isArray(row.completed_milestones) ? row.completed_milestones : []);
  return {
    status: row.status, version: row.onboarding_version,
    currentGameDay: Number(world.rows[0]?.game_day ?? 1), completedMilestones: [...completed],
    milestones: ONBOARDING_MILESTONES, recommendedNext: nextMilestone(completed),
    facts: { resourceBalances: assets.rows, buildingCount: Number(buildings.rows[0]?.count ?? 0), marketOrderCount: Number(orders.rows[0]?.count ?? 0) },
    generatedFrom: 'postgres-canonical-facts',
  };
}

export async function advanceHouseOnboarding(repository: PostgresRepository, houseId: string, milestone: string | undefined, expertSkip: boolean, correlationId: string): Promise<Record<string, unknown>> {
  if (!expertSkip && !ONBOARDING_MILESTONES.some((item) => item.code === milestone)) throw new Error('Unknown onboarding milestone');
  return repository.transaction(async (tx) => {
    const replay = await tx.query('SELECT 1 FROM game_events WHERE correlation_id = $1 LIMIT 1', [correlationId]);
    if (replay.rows[0]) return { ok: true, alreadyProcessed: true, correlationId };
    const gameDay = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
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
