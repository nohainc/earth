import type { PostgresRepository } from './repository.ts';
import { expireMarketOrders, settleMarketBatch } from './market-postgres.ts';
import { listActiveMarketInstruments } from './market-model.ts';
import { refreshMarketCandles } from './market-candles.ts';
import type { FeatureConfig } from './feature-config.ts';

export type MarketBatchResult = { batchesProcessed: number; tradesCreated: number; busy: boolean };

/** Process open clean-schema market batches in order. Custody lives in reservations, not orders. */
export async function processDueMarketBatches(
  repository: PostgresRepository,
  safeProcessedGameDay: number,
  workBudgetMs = 10_000,
  _leaseOwner = `market-scheduler:${crypto.randomUUID()}`,
  _features?: FeatureConfig,
): Promise<MarketBatchResult> {
  const startedAt = Date.now();
  const instruments = (await listActiveMarketInstruments(repository)).filter((instrument) => instrument.instrument_type === 'SPOT');
  let expiryBudget = 100;
  while (expiryBudget > 0 && Date.now() - startedAt < workBudgetMs) {
    const expired = await expireMarketOrders(repository, safeProcessedGameDay, Math.min(expiryBudget, 100));
    expiryBudget -= expired.expired;
    if (expired.expired === 0) break;
  }
  let batchesProcessed = 0;
  let tradesCreated = 0;
  const batches = await repository.query<{ id: string; game_day: number; status: string }>(
    `SELECT id, game_day, status FROM market_batches WHERE status IN ('OPEN','CLEARING') AND game_day <= $1 ORDER BY id`,
    [safeProcessedGameDay],
  );
  for (const batch of batches.rows) {
    if (Date.now() - startedAt >= workBudgetMs) break;
    for (const instrument of instruments) {
      if (Date.now() - startedAt >= workBudgetMs) break;
      const orders = await repository.query<{ count: string }>(
        `SELECT COUNT(*)::TEXT AS count FROM market_orders WHERE batch_id = $1 AND instrument_id = $2 AND status IN ('OPEN','PARTIAL')`,
        [batch.id, instrument.id],
      );
      if (Number(orders.rows[0]?.count ?? 0) === 0) continue;
      const result = await settleMarketBatch(repository, instrument.product, Number(batch.id), Number(batch.game_day), instrument.id);
      tradesCreated += Number(result.fillCount ?? 0);
      await refreshMarketCandles(repository, instrument.id, Number(batch.id));
    }
    await repository.query(`UPDATE market_batches SET status = 'COMPLETED' WHERE id = $1 AND status IN ('OPEN','CLEARING')`, [batch.id]);
    batchesProcessed += 1;
  }
  return { batchesProcessed, tradesCreated, busy: false };
}
