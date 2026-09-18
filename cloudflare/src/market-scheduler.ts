import type { PostgresRepository } from './repository.ts';
import { expireMarketOrders, settleMarketBatch } from './market-postgres.ts';
import { listActiveMarketInstruments, MARKET_BATCH_GAME_MINUTES } from './market-model.ts';
import { refreshMarketCandles } from './market-candles.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';
import type { FeatureConfig } from './feature-config.ts';

export type MarketBatchResult = {
  batchesProcessed: number;
  tradesCreated: number;
  busy: boolean;
  processedThroughMarketBatch: number;
  eligibleMarketBatch: number;
};

type MarketControl = {
  processed_through_market_batch: string;
  status: 'IDLE' | 'PROCESSING' | 'FAILED';
  current_market_batch: string | null;
  lease_owner: string | null;
  lease_expires_at: string | null;
};

export function eligibleMarketBatch(totalGameMinutes: number): number {
  // The currently open partial batch is not cleared until its end minute.
  return Math.floor(Math.max(0, totalGameMinutes) / MARKET_BATCH_GAME_MINUTES) - 1;
}

async function readMarketControl(repository: PostgresRepository): Promise<MarketControl> {
  const result = await repository.query<MarketControl>(
    `SELECT processed_through_market_batch, status, current_market_batch, lease_owner, lease_expires_at
       FROM market_processing_control WHERE id = 'WORLD'`,
  );
  if (!result.rows[0]) throw new Error('Market processing control is not configured');
  return result.rows[0];
}

async function claimNextMarketBatch(repository: PostgresRepository, eligibleBatch: number, leaseOwner: string): Promise<number | null> {
  return repository.transaction(async (tx) => {
    const control = (await tx.query<MarketControl>(
      `SELECT processed_through_market_batch, status, current_market_batch, lease_owner, lease_expires_at
         FROM market_processing_control WHERE id = 'WORLD' FOR UPDATE`,
    )).rows[0];
    if (!control) throw new Error('Market processing control is not configured');
    const leaseActive = control.status === 'PROCESSING'
      && control.lease_expires_at
      && new Date(control.lease_expires_at).getTime() > Date.now()
      && control.lease_owner !== leaseOwner;
    if (leaseActive) return null;
    const nextBatch = Number(control.processed_through_market_batch) + 1;
    if (nextBatch > eligibleBatch) return null;
    await tx.query(
      `UPDATE market_processing_control
          SET status = 'PROCESSING', current_market_batch = $1,
              lease_owner = $2, lease_expires_at = CURRENT_TIMESTAMP + INTERVAL '30 seconds',
              error_message = NULL, updated_at = CURRENT_TIMESTAMP
        WHERE id = 'WORLD'`,
      [nextBatch, leaseOwner],
    );
    return nextBatch;
  });
}

async function completeMarketBatch(repository: PostgresRepository, batch: number, leaseOwner: string): Promise<void> {
  await repository.transaction(async (tx) => {
    const result = await tx.query(
      `UPDATE market_processing_control
          SET processed_through_market_batch = $1, status = 'IDLE', current_market_batch = NULL,
              lease_owner = NULL, lease_expires_at = NULL, updated_at = CURRENT_TIMESTAMP
        WHERE id = 'WORLD' AND status = 'PROCESSING' AND current_market_batch = $1 AND lease_owner = $2`,
      [batch, leaseOwner],
    );
    if (result.rowCount !== 1) throw new Error(`Market batch ${batch} lease was lost before completion`);
  });
}

async function failMarketBatch(repository: PostgresRepository, batch: number, leaseOwner: string, error: unknown): Promise<void> {
  await repository.query(
    `UPDATE market_processing_control
        SET status = 'FAILED', error_message = $3, lease_owner = NULL, lease_expires_at = NULL,
            updated_at = CURRENT_TIMESTAMP
      WHERE id = 'WORLD' AND status = 'PROCESSING' AND current_market_batch = $1 AND lease_owner = $2`,
    [batch, leaseOwner, error instanceof Error ? error.message.slice(0, 1000) : String(error).slice(0, 1000)],
  );
}

/** Cron wakes market processing; authoritative absolute time determines eligibility. */
export async function processDueMarketBatches(
  repository: PostgresRepository,
  workBudgetMs = 10_000,
  leaseOwner = `market-scheduler:${crypto.randomUUID()}`,
  _features?: FeatureConfig,
): Promise<MarketBatchResult> {
  const startedAt = Date.now();
  const clock = await readAuthoritativeGameTime(repository);
  const eligibleBatch = eligibleMarketBatch(clock.totalGameMinutes);
  const instruments = (await listActiveMarketInstruments(repository)).filter((instrument) => instrument.instrument_type === 'SPOT');
  let expiryBudget = 100;
  while (expiryBudget > 0 && Date.now() - startedAt < workBudgetMs) {
    const expired = await expireMarketOrders(repository, clock.gameDay, Math.min(expiryBudget, 100));
    expiryBudget -= expired.expired;
    if (expired.expired === 0) break;
  }

  let batchesProcessed = 0;
  let tradesCreated = 0;
  while (Date.now() - startedAt < workBudgetMs) {
    const batchNumber = await claimNextMarketBatch(repository, eligibleBatch, leaseOwner);
    if (batchNumber === null) break;
    try {
      const batches = await repository.query<{ id: string; game_day: number; status: string }>(
        `SELECT id, game_day, status FROM market_batches
          WHERE correlation_id = $1 AND status IN ('OPEN','CLEARING','FAILED') LIMIT 1`,
        [`market-batch:${batchNumber}`],
      );
      const batch = batches.rows[0];
      if (batch) {
        await repository.query(`UPDATE market_batches SET status = 'CLEARING' WHERE id = $1 AND status IN ('OPEN','FAILED')`, [batch.id]);
        for (const instrument of instruments) {
          const orders = await repository.query<{ count: string }>(
            `SELECT COUNT(*)::TEXT AS count FROM market_orders
              WHERE batch_id = $1 AND instrument_id = $2 AND status IN ('OPEN','PARTIAL')`,
            [batch.id, instrument.id],
          );
          if (Number(orders.rows[0]?.count ?? 0) === 0) continue;
          const result = await settleMarketBatch(repository, instrument.product, Number(batch.id), Number(batch.game_day), instrument.id);
          tradesCreated += Number(result.fillCount ?? 0);
          await refreshMarketCandles(repository, instrument.id, Number(batch.id));
        }
        await repository.query(`UPDATE market_batches SET status = 'COMPLETED' WHERE id = $1 AND status IN ('CLEARING','OPEN')`, [batch.id]);
      }
      await completeMarketBatch(repository, batchNumber, leaseOwner);
      batchesProcessed += 1;
    } catch (error) {
      await failMarketBatch(repository, batchNumber, leaseOwner, error).catch(() => {});
      throw error;
    }
  }

  const control = await readMarketControl(repository);
  return {
    batchesProcessed,
    tradesCreated,
    busy: Number(control.processed_through_market_batch) < eligibleBatch,
    processedThroughMarketBatch: Number(control.processed_through_market_batch),
    eligibleMarketBatch: eligibleBatch,
  };
}
