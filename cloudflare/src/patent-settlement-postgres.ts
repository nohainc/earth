import type { PostgresRepository } from './repository.ts';

// @mutation-boundary deterministic-settlement: patent grants and public-domain transitions are database-authoritative.
// @mutation-boundary caller-owned-transaction: both operations run inside the phase transaction.
export async function settlePatentExpirations(
  repository: PostgresRepository,
  gameDay: number,
): Promise<{ gameDay: number; patentsGranted: number; technologiesPublic: number }> {
  const granted = await repository.query<{ count: string }>(
    'SELECT earth_grant_completed_technology_patents($1) AS count',
    [gameDay],
  );
  const publicDomain = await repository.query<{ count: string }>(
    'SELECT earth_finalize_technology_public_domain($1) AS count',
    [gameDay],
  );
  return {
    gameDay,
    patentsGranted: Number(granted.rows[0]?.count ?? 0),
    technologiesPublic: Number(publicDomain.rows[0]?.count ?? 0),
  };
}
