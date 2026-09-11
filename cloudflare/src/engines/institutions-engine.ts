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

  return {
    proposalsClosed: closedProposals.rows.length,
    citiesUpdated: 0,
  };
}
