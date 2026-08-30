import type { PostgresRepository } from '../repository.ts';

export interface InstitutionsSettlementResult {
  proposalsClosed: number;
  citiesUpdated: number;
}

export async function settleContinuousInstitutions(
  repo: PostgresRepository,
  gameDay: number,
  gameMinute: number,
): Promise<InstitutionsSettlementResult> {
  // 1. Close expired governance proposals
  const closedProposals = await repo.query<{ id: string }>(
    `UPDATE proposals
     SET status = 'closed', updated_at = CURRENT_TIMESTAMP
     WHERE status = 'open' AND (closes_game_day < $1 OR (closes_game_day = $1 AND closes_game_minute <= $2))
     RETURNING id`,
    [gameDay, gameMinute],
  );

  // 2. Adjust municipal capacity ratios based on budgets
  await repo.query(
    `UPDATE cities
     SET housing_capacity = LEAST(1000000, housing_capacity + FLOOR(LEAST(5, COALESCE((SELECT amount FROM budgets WHERE institution_id = cities.institution_id AND category = 'housing' ORDER BY game_day DESC LIMIT 1), 0) / 1000.0))::integer),
         energy_capacity = LEAST(1000000, energy_capacity + FLOOR(LEAST(5, COALESCE((SELECT amount FROM budgets WHERE institution_id = cities.institution_id AND category = 'energy' ORDER BY game_day DESC LIMIT 1), 0) / 1000.0))::integer),
         connectivity_capacity = LEAST(1000000, connectivity_capacity + FLOOR(LEAST(5, COALESCE((SELECT amount FROM budgets WHERE institution_id = cities.institution_id AND category = 'connectivity' ORDER BY game_day DESC LIMIT 1), 0) / 1000.0))::integer),
         health_capacity = LEAST(100, health_capacity + FLOOR(LEAST(5, COALESCE((SELECT amount FROM budgets WHERE institution_id = cities.institution_id AND category IN ('health','public-services','maintenance') ORDER BY game_day DESC LIMIT 1), 0) / 1000.0))::integer)
     WHERE status = 'active'`,
  );

  return {
    proposalsClosed: closedProposals.rows.length,
    citiesUpdated: 1,
  };
}
