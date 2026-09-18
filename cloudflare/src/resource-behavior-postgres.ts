import type { PostgresRepository } from './repository.ts';

export async function getResourceBehaviorMetadata(repository: PostgresRepository): Promise<Record<string, unknown>> {
  const result = await repository.query<{
    code: string;
    behavior: string;
    storage_limit_units: string | null;
    delivery_period_game_days: string;
    decay_bps_per_day: number;
    settlement_mode: string;
    definition_version: string;
    persistence_class: string;
  }>(`SELECT asset.code, behavior, storage_limit_units::TEXT, delivery_period_game_days::TEXT,
             decay_bps_per_day, settlement_mode, definition_version, persistence_class
        FROM resource_behavior_metadata metadata
        JOIN economic_assets asset ON asset.id = metadata.asset_id
       WHERE asset.asset_kind = 'RESOURCE'
       ORDER BY asset.id`);
  return {
    resources: result.rows.map((row) => ({
      code: row.code,
      behavior: row.behavior,
      storageLimitUnits: row.storage_limit_units,
      deliveryPeriodGameDays: Number(row.delivery_period_game_days),
      decayBpsPerDay: row.decay_bps_per_day,
      settlementMode: row.settlement_mode,
      definitionVersion: row.definition_version,
      persistenceClass: row.persistence_class,
    })),
    stagedSemantics: { phaseA: 'metadata', phaseB: 'food-decay', phaseC: 'flow-capacity-entitlements' },
    generatedFrom: 'postgres-canonical-facts',
  };
}
