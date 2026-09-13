import type { PostgresRepository } from './repository.ts';

export type LifeMaintenanceEstimate = { dailyCredits: number; resources: Record<string, number> };
export function estimateLifeMaintenance(): LifeMaintenanceEstimate { return { dailyCredits: 0, resources: {} }; }
export async function settleLifeMaintenance(): Promise<number> { return 0; }
export async function settleLifeMaintenanceInTransaction(_tx: PostgresRepository): Promise<number> { return 0; }
