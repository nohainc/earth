import type { PostgresRepository } from './repository.ts';

/** Provision range partitions before the accelerated game clock reaches them. */
export async function provisionEconomicEntryPartitions(
  repository: PostgresRepository,
  gameDay: number,
  rangesAhead = 5,
): Promise<number> {
  const result = await repository.query<{ provisioned: number }>(
    'SELECT earth_provision_economic_entry_partitions($1::bigint, $2::integer) AS provisioned',
    [gameDay, rangesAhead],
  );
  return Number(result.rows[0]?.provisioned ?? 0);
}

