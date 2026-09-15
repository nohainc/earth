import type { PostgresRepository } from './repository.ts';

// @mutation-boundary deterministic-settlement: reconcile Human-scoped authority after lifecycle changes.
// @mutation-boundary caller-owned-transaction: invoked only from the daily settlement transaction.
export async function refreshPostSuccessionAccess(
  repository: PostgresRepository,
  gameDay: number,
): Promise<{ gameDay: number; grantsExpired: number }> {
  const result = await repository.query<{ id: string }>(
    `UPDATE organization_office_grants g
        SET status = 'EXPIRED',
            effective_to_game_day = $1,
            updated_at = CURRENT_TIMESTAMP
       FROM humans h
      WHERE g.principal_type = 'HUMAN'
        AND g.principal_id = h.id
        AND g.status = 'ACTIVE'
        AND (
          h.status <> 'ACTIVE'
          OR (g.effective_to_game_day IS NOT NULL AND g.effective_to_game_day < $1)
        )
      RETURNING g.id`,
    [gameDay],
  );
  return { gameDay, grantsExpired: result.rows.length };
}
