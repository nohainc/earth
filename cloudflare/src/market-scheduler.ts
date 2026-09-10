import type { PostgresRepository } from './repository.ts';
import { settleMarket } from './market-postgres.ts';

const PRODUCTS = ['food', 'material', 'components', 'energy', 'compute'];
const BATCH_GAME_MINUTES = 60;

export type MarketBatchResult = { batchesProcessed: number; tradesCreated: number; busy: boolean };

/** Process immutable hourly game-time batches, including batches missed by Cron. */
export async function processDueMarketBatches(
  repository: PostgresRepository,
  safeProcessedGameDay: number,
  workBudgetMs = 10_000,
  leaseOwner = `market-scheduler:${crypto.randomUUID()}`,
): Promise<MarketBatchResult> {
  const startedAt = Date.now();
  const maxBatch = Math.floor((safeProcessedGameDay * 1440 + 1439) / BATCH_GAME_MINUTES);
  let batchesProcessed = 0;
  let tradesCreated = 0;
  let busy = false;

  for (const product of PRODUCTS) {
    const last = await repository.query<{ batch_id: string | null }>(
      `SELECT COALESCE(
               (SELECT MIN(expected.batch_id)
                  FROM generate_series(0, $2) AS expected(batch_id)
                 WHERE NOT EXISTS (
                   SELECT 1 FROM market_batch_runs r
                    WHERE r.product = $1 AND r.batch_id = expected.batch_id AND r.status = 'completed'
                 )),
               $2 + 1
             )::text AS batch_id`, [product, maxBatch],
    );
    let batchId = Number(last.rows[0]?.batch_id ?? maxBatch + 1);
    while (batchId <= maxBatch && Date.now() - startedAt < workBudgetMs) {
      const claim = await repository.query<{ claimed: boolean; status: string }>(
        'SELECT * FROM earth_claim_market_batch($1,$2,$3,300)', [batchId, product, leaseOwner],
      );
      if (!claim.rows[0]?.claimed) {
        if (claim.rows[0]?.status === 'busy') busy = true;
        break;
      }

      const batchGameDay = Math.floor((batchId * BATCH_GAME_MINUTES) / 1440);
      await repository.query(
        `UPDATE market_prices
            SET price = GREATEST(1, LEAST(1000000, ROUND((price *
              (1.0 + LEAST(0.05, GREATEST(-0.05,
                (demand - supply) / GREATEST(1.0, supply + demand)))))::numeric, 2))),
                game_day = $2, last_market_batch_id = $3
          WHERE product = $1 AND COALESCE(last_market_batch_id, -1) < $3`,
        [product, batchGameDay, batchId],
      );

      let ordersProcessed = 0;
      let tradesCreatedForBatch = 0;
      let exhausted = false;
      while (!exhausted && Date.now() - startedAt < workBudgetMs) {
        const result = await settleMarket(repository, product, batchGameDay);
        ordersProcessed += 1;
        if (!result.filled) exhausted = true;
        else { tradesCreatedForBatch += 1; tradesCreated += 1; }
      }
      if (!exhausted) {
        await repository.query(
          `UPDATE market_batch_runs
              SET status = 'pending', orders_processed = orders_processed + $3,
                  trades_created = trades_created + $4, lease_owner = NULL,
                  lease_expires_at = NULL, updated_at = CURRENT_TIMESTAMP
            WHERE batch_id = $1 AND product = $2 AND status = 'running' AND lease_owner = $5`,
          [batchId, product, ordersProcessed, tradesCreatedForBatch, leaseOwner],
        );
        break;
      }
      await repository.query(
        `UPDATE market_batch_runs
            SET status = 'completed', completed_at = CURRENT_TIMESTAMP,
                orders_processed = orders_processed + $3, trades_created = trades_created + $4,
                lease_owner = NULL, lease_expires_at = NULL, updated_at = CURRENT_TIMESTAMP
          WHERE batch_id = $1 AND product = $2 AND status = 'running' AND lease_owner = $5`,
        [batchId, product, ordersProcessed, tradesCreatedForBatch, leaseOwner],
      );
      batchesProcessed += 1;
      batchId += 1;
    }
  }
  return { batchesProcessed, tradesCreated, busy };
}
