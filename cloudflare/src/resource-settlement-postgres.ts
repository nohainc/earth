import { settleResourcePersistenceAndDecay } from './v5-resource-persistence-postgres.ts';

const BPS_DENOMINATOR = 10_000n;

export function calculatePerishableDecayUnits(balanceUnits: bigint, decayBpsPerDay: number): bigint {
  if (balanceUnits < 0n) throw new Error('Resource balance cannot be negative');
  if (!Number.isInteger(decayBpsPerDay) || decayBpsPerDay < 0 || decayBpsPerDay > 10_000) throw new Error('Decay rate is outside bounds');
  return balanceUnits * BigInt(decayBpsPerDay) / BPS_DENOMINATOR;
}

/** Apply staged perishable-stock loss and flow expiration once at day close. The loss is an
 * explicit resource-consumption transaction, so conservation reports can
 * distinguish authorized decay from an unexplained balance change. */
// @mutation-boundary deterministic-settlement: the day/owner key and transaction correlation make retries safe.
// @mutation-boundary caller-owned-transaction: decay is an owner-sharded settlement phase.
export async function settlePerishableResourceDecay(
  repository: PostgresRepository,
  day: number,
  shard = 0,
  shardCount = 1,
): Promise<{ expiredUnits: string; housesAffected: number }> {
  const result = await settleResourcePersistenceAndDecay(repository, day, shard, shardCount);
  return {
    expiredUnits: result.expiredUnits,
    housesAffected: result.housesAffected,
  };
}

