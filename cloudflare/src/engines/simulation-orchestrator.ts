import type { PostgresRepository } from '../repository.ts';
import { deriveContinuousGameTime, REAL_SECONDS_PER_GAME_MINUTE } from './time-engine.ts';
import { settleContinuousFinancials } from './financial-engine.ts';
import { settleContinuousMarket } from './market-engine.ts';
import { settleContinuousInstitutions } from './institutions-engine.ts';
import { settleContinuousLifecycle } from './lifecycle-engine.ts';
import { settleContinuousRankings } from './rankings-engine.ts';
import { computeResourceFlows, type ResourceFlowMap } from './resource-flow-engine.ts';

export interface SimulationReconciliation {
  gameDay: number;
  gameMinute: number;
  elapsedSeconds: number;
  elapsedDays: number;
  productionEvents: number;
  ordersSettled: number;
  flows?: ResourceFlowMap;
}

export async function reconcileWorldSimulation(
  repo: PostgresRepository,
  viewerId?: string,
  nowMs?: number,
): Promise<SimulationReconciliation> {
  const currentRealMs = nowMs ?? Date.now();

  return repo.transaction(async (tx) => {
    // 1. Fetch current world state
    const worldRow = (
      await tx.query<{
        game_day: number;
        game_minute: number;
        genesis_at: string | null;
        simulated_day_offset: number | null;
        last_scheduler_at: string | null;
      }>("SELECT game_day, game_minute, genesis_at, simulated_day_offset, last_scheduler_at FROM world_state WHERE id = 'WORLD' FOR UPDATE")
    ).rows[0];

    const prevDay = Number(worldRow?.game_day ?? 184);
    const prevMinute = Number(worldRow?.game_minute ?? 0);
    const lastSimulatedMs = worldRow?.last_scheduler_at
      ? new Date(worldRow.last_scheduler_at).getTime()
      : currentRealMs - 5000;

    const rawElapsedMs = Math.max(0, currentRealMs - lastSimulatedMs);
    // Cap single catch-up jump to 24 real-world hours to avoid unbounded transaction overhead
    const elapsedRealMs = Math.min(86400000, rawElapsedMs);
    const elapsedSeconds = Math.floor(elapsedRealMs / 1000);

    // Compute continuous game time
    const time = deriveContinuousGameTime({
      nowMs: currentRealMs,
      genesisAt: worldRow?.genesis_at,
      simulatedDayOffset: worldRow?.simulated_day_offset,
    });

    const currDay = Math.floor(time.gameDay > 0 ? time.gameDay : prevDay);
    const currMinute = Math.floor(time.gameMinute);
    const elapsedDays = Math.max(0, elapsedSeconds / 1440);

    let productionEvents = 0;
    let ordersSettled = 0;

    // 2. Run simulation engines if time has elapsed
    if (elapsedSeconds >= 1) {
      await settleContinuousFinancials(tx, elapsedDays, currDay);
      const marketRes = await settleContinuousMarket(tx, currDay);
      ordersSettled = marketRes.settledOrders;

      await settleContinuousInstitutions(tx, currDay, currMinute);
      await settleContinuousLifecycle(tx, currDay, prevDay);
      if (currDay !== prevDay || elapsedDays >= 1) {
        await settleContinuousRankings(tx, currDay, prevDay);
      }

      // Update world_state
      await tx.query(
        "UPDATE world_state SET game_day = $1, game_minute = $2, last_scheduler_at = to_timestamp($3 / 1000.0) WHERE id = 'WORLD'",
        [currDay, currMinute, currentRealMs],
      );
    }

    // 3. Compute viewer continuous flows if requested
    let flows: ResourceFlowMap | undefined;
    if (viewerId) {
      flows = await computeResourceFlows(tx, viewerId);
    }

    return {
      gameDay: currDay,
      gameMinute: currMinute,
      elapsedSeconds,
      elapsedDays,
      productionEvents,
      ordersSettled,
      flows,
    };
  });
}
