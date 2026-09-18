import type { PostgresRepository } from './repository.ts';

export type ResourcePersistenceClass = 'DURABLE' | 'PERISHABLE' | 'FLOW';
export type StorageType = 'BATTERY_STORAGE' | 'FOOD_RESERVE' | 'COMPUTE_STORAGE' | 'GENERIC_STORAGE';
export type StorageSourceType = 'BUILDING' | 'TECHNOLOGY' | 'POLICY' | 'MANUAL';

export interface ResourcePersistenceMetadata {
  assetId: number;
  code: string;
  persistenceClass: ResourcePersistenceClass;
  decayBpsPerDay: number;
  storageLimitUnits: string | null;
  settlementMode: string;
  definitionVersion: string;
}

export interface OwnerStorageCapacity {
  capacityUnits: bigint;
  decayReductionBps: number;
}

const RESOURCE_CONSUMPTION_OWNER = 'ECON-RESOURCE-CONSUMPTION';
const BPS_DENOMINATOR = 10_000n;

/**
 * Get persistence metadata for all economic assets.
 */
export async function getResourcePersistenceMetadata(repository: PostgresRepository): Promise<ResourcePersistenceMetadata[]> {
  const result = await repository.query<{
    asset_id: number;
    code: string;
    persistence_class: ResourcePersistenceClass;
    decay_bps_per_day: number;
    storage_limit_units: string | null;
    settlement_mode: string;
    definition_version: string;
  }>(`
    SELECT asset.id AS asset_id, asset.code, metadata.persistence_class,
           metadata.decay_bps_per_day, metadata.storage_limit_units::TEXT,
           metadata.settlement_mode, metadata.definition_version
      FROM resource_behavior_metadata metadata
      JOIN economic_assets asset ON asset.id = metadata.asset_id
     WHERE asset.asset_kind = 'RESOURCE'
     ORDER BY asset.id
  `);

  return result.rows.map((row) => ({
    assetId: row.asset_id,
    code: row.code,
    persistenceClass: row.persistence_class,
    decayBpsPerDay: row.decay_bps_per_day,
    storageLimitUnits: row.storage_limit_units,
    settlementMode: row.settlement_mode,
    definitionVersion: row.definition_version,
  }));
}

/**
 * Resolve effective storage capacity and decay reduction for an owner and asset.
 */
export async function resolveOwnerStorageCapacity(
  repository: PostgresRepository,
  ownerEconomicId: string,
  assetId: number,
  gameDay: number = 1,
): Promise<OwnerStorageCapacity> {
  const res = await repository.query<{
    total_capacity: string | null;
    total_decay_reduction_bps: number | null;
  }>(`
    SELECT COALESCE(SUM(storage_capacity_units), 0)::TEXT AS total_capacity,
           COALESCE(SUM(decay_reduction_bps), 0)::INTEGER AS total_decay_reduction_bps
      FROM owner_storage_capacities
     WHERE owner_economic_id = $1
       AND asset_id = $2
       AND status = 'ACTIVE'
       AND effective_from_game_day <= $3
       AND (effective_to_game_day IS NULL OR effective_to_game_day >= $3)
  `, [ownerEconomicId, assetId, gameDay]);

  const row = res.rows[0];
  const capacityUnits = BigInt(row?.total_capacity || '0');
  const decayReductionBps = Math.min(10000, Math.max(0, row?.total_decay_reduction_bps || 0));

  return { capacityUnits, decayReductionBps };
}

/**
 * Grant or register a storage capacity modifier for an owner.
 */
export async function grantOwnerStorageCapacity(
  repository: PostgresRepository,
  input: {
    id?: string;
    ownerEconomicId: string;
    assetCode: string;
    storageType: StorageType;
    capacityUnits: bigint;
    decayReductionBps?: number;
    sourceType: StorageSourceType;
    sourceId: string;
    effectiveFromGameDay?: number;
    effectiveToGameDay?: number;
  },
): Promise<void> {
  const assetRes = await repository.query<{ id: number }>(
    `SELECT id FROM economic_assets WHERE code = $1`,
    [input.assetCode],
  );
  if (assetRes.rows.length === 0) {
    throw new Error(`Asset not found: ${input.assetCode}`);
  }
  const assetId = assetRes.rows[0].id;
  const id = input.id || `storage:${input.ownerEconomicId}:${input.assetCode}:${input.sourceType}:${input.sourceId}`;
  const effectiveFrom = input.effectiveFromGameDay ?? 1;
  const decayReduction = input.decayReductionBps ?? 0;

  await repository.query(`
    INSERT INTO owner_storage_capacities
      (id, owner_economic_id, asset_id, storage_type, storage_capacity_units, decay_reduction_bps,
       source_type, source_id, status, effective_from_game_day, effective_to_game_day)
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'ACTIVE', $9, $10)
    ON CONFLICT (id) DO UPDATE SET
      storage_capacity_units = EXCLUDED.storage_capacity_units,
      decay_reduction_bps = EXCLUDED.decay_reduction_bps,
      status = 'ACTIVE',
      effective_from_game_day = EXCLUDED.effective_from_game_day,
      effective_to_game_day = EXCLUDED.effective_to_game_day,
      updated_at = CURRENT_TIMESTAMP
  `, [
    id,
    input.ownerEconomicId,
    assetId,
    input.storageType,
    input.capacityUnits.toString(),
    decayReduction,
    input.sourceType,
    input.sourceId,
    effectiveFrom,
    input.effectiveToGameDay ?? null,
  ]);
}

/**
 * Pure calculation of decay or flow expiration units based on balance, persistence class, and storage modifier.
 */
export function calculateResourceDecayUnits(params: {
  balanceUnits: bigint;
  persistenceClass: ResourcePersistenceClass;
  baseDecayBps: number;
  storageCapacityUnits: bigint;
  decayReductionBps: number;
}): bigint {
  const { balanceUnits, persistenceClass, baseDecayBps, storageCapacityUnits, decayReductionBps } = params;
  if (balanceUnits <= 0n) return 0n;

  switch (persistenceClass) {
    case 'DURABLE':
      return 0n;

    case 'PERISHABLE': {
      // Storage protects up to storageCapacityUnits from decay
      const decayableBalance = balanceUnits > storageCapacityUnits ? balanceUnits - storageCapacityUnits : 0n;
      if (decayableBalance <= 0n) return 0n;

      const effectiveDecayBps = Math.max(0, Math.min(10000, baseDecayBps - decayReductionBps));
      if (effectiveDecayBps <= 0) return 0n;

      return (decayableBalance * BigInt(effectiveDecayBps)) / BPS_DENOMINATOR;
    }

    case 'FLOW': {
      // Flow unbuffered excess beyond storage capacity expires at day close
      const unbufferedExcess = balanceUnits > storageCapacityUnits ? balanceUnits - storageCapacityUnits : 0n;
      return unbufferedExcess;
    }

    default:
      return 0n;
  }
}

/**
 * Settle resource persistence, perishable decay, and flow expiration at end of day (Phase 127).
 * Works across all active House and Corporation inventory accounts.
 */
export async function settleResourcePersistenceAndDecay(
  repository: PostgresRepository,
  day: number,
  shard = 0,
  shardCount = 1,
): Promise<{
  expiredUnits: string;
  housesAffected: number;
  expiredUnitsByAsset: Record<string, string>;
  ownersAffected: number;
}> {
  const metadataList = await getResourcePersistenceMetadata(repository);
  // Only process PERISHABLE and FLOW resources that have potential decay or expiration
  const decayableResources = metadataList.filter(
    (m) => m.persistenceClass === 'PERISHABLE' || m.persistenceClass === 'FLOW',
  );

  if (decayableResources.length === 0) {
    return { expiredUnits: '0', housesAffected: 0, expiredUnitsByAsset: {}, ownersAffected: 0 };
  }

  let totalExpired = 0n;
  const expiredByAsset: Record<string, bigint> = {};
  const affectedOwners = new Set<string>();
  let housesAffectedCount = 0;

  for (const meta of decayableResources) {
    expiredByAsset[meta.code] = 0n;

    // Retrieve sink account for this asset
    const sinkRes = await repository.query<{ id: string }>(`
      SELECT account.id::TEXT AS id
        FROM economic_accounts account
        JOIN owner_registry owner ON owner.economic_id = account.owner_economic_id
       WHERE owner.economic_id = $1
         AND owner.owner_type = 'SYSTEM'
         AND account.asset_id = $2
         AND account.account_type = 'SYSTEM_ACCOUNT'
         AND account.status = 'ACTIVE'
       LIMIT 1
    `, [RESOURCE_CONSUMPTION_OWNER, meta.assetId]);

    const sink = sinkRes.rows[0];
    if (!sink) {
      throw new Error(`Sink account not found for asset ${meta.code} (${meta.assetId})`);
    }

    // Query all active inventory accounts for Houses and Corporations in this shard
    const accountsRes = await repository.query<{
      economic_id: string;
      owner_type: string;
      account_id: string;
      balance_units: string;
    }>(`
      SELECT owner.economic_id, owner.owner_type, inventory.id::TEXT AS account_id, inventory.balance_units::TEXT AS balance_units
        FROM owner_registry owner
        JOIN economic_accounts inventory ON inventory.owner_economic_id = owner.economic_id
         AND inventory.asset_id = $1
         AND inventory.account_type = 'INVENTORY'
         AND inventory.status = 'ACTIVE'
       WHERE owner.owner_type IN ('HOUSE', 'CORPORATION')
         AND MOD(ABS(hashtextextended(owner.economic_id, 0)), $2) = $3
       ORDER BY owner.economic_id
    `, [meta.assetId, shardCount, shard]);

    for (const row of accountsRes.rows) {
      const balance = BigInt(row.balance_units);
      if (balance <= 0n) continue;

      const storage = await resolveOwnerStorageCapacity(repository, row.economic_id, meta.assetId, day);
      const decayUnits = calculateResourceDecayUnits({
        balanceUnits: balance,
        persistenceClass: meta.persistenceClass,
        baseDecayBps: meta.decayBpsPerDay,
        storageCapacityUnits: storage.capacityUnits,
        decayReductionBps: storage.decayReductionBps,
      });

      if (decayUnits <= 0n) continue;

      const reasonCode = meta.persistenceClass === 'FLOW'
        ? `${meta.code.toLowerCase()}_flow_expiration`
        : `${meta.code.toLowerCase()}_perishability`;

      const reasonSinkCode = `${reasonCode}_sink`;
      const correlationId = meta.code === 'FOOD'
        ? `food-decay:${row.economic_id}:${day}`
        : `resource-decay:${meta.code.toLowerCase()}:${row.economic_id}:${day}`;

      await repository.query(`
        SELECT earth_post_transaction(
          $1, $2, 1439, 'RESOURCE_CONSUMPTION', 'SYSTEM_CONSUMPTION', $3, 'v5-resource-persistence-v1', $4::JSONB
        )
      `, [
        correlationId,
        day,
        row.economic_id,
        JSON.stringify([
          { account_id: row.account_id, asset_id: meta.assetId, delta_units: (-decayUnits).toString(), reason_code: reasonCode },
          { account_id: sink.id, asset_id: meta.assetId, delta_units: decayUnits.toString(), reason_code: reasonSinkCode },
        ]),
      ]);

      totalExpired += decayUnits;
      expiredByAsset[meta.code] += decayUnits;
      affectedOwners.add(row.economic_id);
      if (row.owner_type === 'HOUSE') {
        housesAffectedCount += 1;
      }
    }
  }

  const resultByAsset: Record<string, string> = {};
  for (const [code, val] of Object.entries(expiredByAsset)) {
    resultByAsset[code] = val.toString();
  }

  return {
    expiredUnits: totalExpired.toString(),
    housesAffected: housesAffectedCount,
    expiredUnitsByAsset: resultByAsset,
    ownersAffected: affectedOwners.size,
  };
}
