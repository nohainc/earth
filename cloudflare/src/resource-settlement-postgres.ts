import type { PostgresRepository } from './repository.ts';

const FOOD_CODE = 'FOOD';
const RESOURCE_CONSUMPTION_OWNER = 'ECON-RESOURCE-CONSUMPTION';
const BPS_DENOMINATOR = 10_000n;

export function calculatePerishableDecayUnits(balanceUnits: bigint, decayBpsPerDay: number): bigint {
  if (balanceUnits < 0n) throw new Error('Resource balance cannot be negative');
  if (!Number.isInteger(decayBpsPerDay) || decayBpsPerDay < 0 || decayBpsPerDay > 10_000) throw new Error('Decay rate is outside bounds');
  return balanceUnits * BigInt(decayBpsPerDay) / BPS_DENOMINATOR;
}

/** Apply staged perishable-stock loss once at day close. The loss is an
 * explicit resource-consumption transaction, so conservation reports can
 * distinguish authorized decay from an unexplained balance change. */
// @mutation-boundary deterministic-settlement: the day/owner key and transaction correlation make retries safe.
// @mutation-boundary caller-owned-transaction: decay is an owner-sharded settlement phase.
export async function settlePerishableResourceDecay(repository: PostgresRepository, day: number, shard = 0, shardCount = 1): Promise<{ expiredUnits: string; housesAffected: number }> {
  const metadata = (await repository.query<{ asset_id: number; decay_bps_per_day: number }>(
    `SELECT asset.id AS asset_id, metadata.decay_bps_per_day
       FROM resource_behavior_metadata metadata JOIN economic_assets asset ON asset.id = metadata.asset_id
      WHERE asset.code = $1 AND metadata.behavior = 'PERISHABLE_STOCK' AND metadata.settlement_mode = 'EXPLICIT_SINK'`, [FOOD_CODE],
  )).rows[0];
  if (!metadata || metadata.decay_bps_per_day <= 0) return { expiredUnits: '0', housesAffected: 0 };
  const sink = (await repository.query<{ id: string }>(
    `SELECT account.id::TEXT AS id FROM economic_accounts account JOIN owner_registry owner ON owner.economic_id = account.owner_economic_id
      WHERE owner.economic_id = $1 AND owner.owner_type = 'SYSTEM' AND account.asset_id = $2 AND account.account_type = 'SYSTEM_ACCOUNT' AND account.status = 'ACTIVE' LIMIT 1`, [RESOURCE_CONSUMPTION_OWNER, metadata.asset_id],
  )).rows[0];
  if (!sink) throw new Error('Perishable resource sink account is not provisioned');
  const houses = await repository.query<{ economic_id: string; account_id: string; balance_units: string }>(
    `SELECT owner.economic_id, inventory.id::TEXT AS account_id, inventory.balance_units::TEXT AS balance_units
       FROM owner_registry owner JOIN economic_accounts inventory ON inventory.owner_economic_id = owner.economic_id
        AND inventory.asset_id = $1 AND inventory.account_type = 'INVENTORY' AND inventory.status = 'ACTIVE'
      WHERE owner.owner_type = 'HOUSE' AND MOD(ABS(hashtextextended(owner.economic_id, 0)), $2) = $3
      ORDER BY owner.economic_id`, [metadata.asset_id, shardCount, shard],
  );
  let expired = 0n;
  let affected = 0;
  for (const house of houses.rows) {
    const balance = BigInt(house.balance_units);
    const decay = calculatePerishableDecayUnits(balance, metadata.decay_bps_per_day);
    if (decay <= 0n) continue;
    await repository.query(
      `SELECT earth_post_transaction($1, $2, 1439, 'RESOURCE_CONSUMPTION', 'SYSTEM_CONSUMPTION', $3, 'resource-decay-v1', $4::JSONB)`,
      [`food-decay:${house.economic_id}:${day}`, day, house.economic_id, JSON.stringify([
        { account_id: house.account_id, asset_id: metadata.asset_id, delta_units: (-decay).toString(), reason_code: 'food_perishability' },
        { account_id: sink.id, asset_id: metadata.asset_id, delta_units: decay.toString(), reason_code: 'food_perishability_sink' },
      ])],
    );
    expired += decay;
    affected += 1;
  }
  return { expiredUnits: expired.toString(), housesAffected: affected };
}
