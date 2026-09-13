import type { PostgresRepository } from './repository.ts';

/** The clean baseline has one daily settlement coordinator. */
export async function rebuildDailySettlementProfile(_repository: PostgresRepository, _ownerId: string, _gameDay: number): Promise<void> {}

export async function catchupOwnerSettlement(_repository: PostgresRepository, ownerId: string, targetDay?: number): Promise<{ ownerId: string; elapsedDays: number; lastSettledDay: number; settled: boolean }> {
  return { ownerId, elapsedDays: 0, lastSettledDay: targetDay ?? 0, settled: true };
}

export async function rebuildDirtyDailySettlementProfiles(_repository: PostgresRepository, _gameDay: number): Promise<number> { return 0; }

export async function applyPreparedSettlementProfiles(_repository: PostgresRepository, _gameDay: number): Promise<number> { return 0; }

export async function markDailySettlementProfileDirty(_repository: PostgresRepository, _ownerId: string): Promise<void> {}
