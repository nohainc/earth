import type { PostgresRepository } from './repository.ts';
import { settleMarketBatch } from './market-postgres.ts';
import { GAME_DAY_MINUTES, gamePosition, marketBatchRange } from './market-time.ts';
import { listActiveMarketInstruments, MARKET_BATCH_GAME_MINUTES } from './market-model.ts';
import { rebuildMarketInstrumentState, refreshMarketPriceProjection } from './market-state.ts';
import { refreshMarketCandles } from './market-candles.ts';
import { settleDueDeliveryFutures } from './market-futures-settlement.ts';
import type { FeatureConfig } from './feature-config.ts';

export type MarketBatchResult = { batchesProcessed: number; tradesCreated: number; futuresSettled: number; busy: boolean };

/** Process immutable market batches in strict order, including batches missed by Cron. */
export async function processDueMarketBatches(
  repository: PostgresRepository,
  safeProcessedGameDay: number,
  workBudgetMs = 10_000,
  leaseOwner = `market-scheduler:${crypto.randomUUID()}`,
  features?: FeatureConfig,
): Promise<MarketBatchResult> {
  const startedAt = Date.now();
  const maxBatch = Math.ceil((safeProcessedGameDay * GAME_DAY_MINUTES) / MARKET_BATCH_GAME_MINUTES) - 1;
  const allInstruments = await listActiveMarketInstruments(repository);
  const instruments = allInstruments.filter((instrument) => features?.futures !== false || instrument.instrument_type !== 'DELIVERY_FUTURE');
  let batchesProcessed = 0;
  let tradesCreated = 0;
  let settledFutures = 0;
  let busy = false;

  while (Date.now() - startedAt < workBudgetMs) {
    const next = await repository.query<{ batch_id: string }>(
      `SELECT (COALESCE(MAX(id) FILTER (WHERE status = 'completed'), -1) + 1)::TEXT AS batch_id
         FROM market_batches`,
    );
    const batchId = Number(next.rows[0]?.batch_id ?? 0);
    // The due-batch boundary is equivalent to: batchId <= maxBatch.
    if (batchId > maxBatch) break;
    const range = marketBatchRange(batchId, MARKET_BATCH_GAME_MINUTES);
    const batchGameDay = gamePosition(range.startMinute).gameDay;
    const batchRulesVersion = instruments[0]?.rules_version ?? 'market-v2';
    const batchRulesSnapshot = JSON.stringify({ rulesVersion: batchRulesVersion, batchDurationMinutes: MARKET_BATCH_GAME_MINUTES });
    await repository.query(
      `INSERT INTO market_batches (id, start_total_game_minute, end_total_game_minute, status, rules_version, rules_snapshot)
       VALUES ($1,$2,$3,'clearing',$4,$5::JSONB)
       ON CONFLICT (id) DO UPDATE SET status = CASE WHEN market_batches.status = 'pending' THEN 'clearing' ELSE market_batches.status END,
                                      started_at = COALESCE(market_batches.started_at, CURRENT_TIMESTAMP)`,
      [batchId, range.startMinute, range.endMinute, batchRulesVersion, batchRulesSnapshot],
    );
    let batchComplete = true;
    for (const instrument of instruments) {
      if (Date.now() - startedAt >= workBudgetMs) { batchComplete = false; break; }
      const claim = await repository.query<{ claimed: boolean; status: string }>(
        'SELECT * FROM earth_claim_market_batch_instrument($1,$2,$3,300)', [batchId, instrument.id, leaseOwner],
      );
      if (!claim.rows[0]?.claimed) {
        if (claim.rows[0]?.status === 'busy') busy = true;
        if (claim.rows[0]?.status !== 'completed') batchComplete = false;
        continue;
      }
      const before = await rebuildMarketInstrumentState(repository, instrument.id);
      await repository.query(
        `UPDATE market_batch_instruments
            SET eligible_order_count = (SELECT COUNT(*) FROM market_orders WHERE instrument_id = $2 AND eligible_batch_id <= $1 AND status IN ('open','partial')),
                previous_price_units = $3
          WHERE batch_id = $1 AND instrument_id = $2 AND lease_owner = $4`,
        [batchId, instrument.id, before.last_clearing_price_units, leaseOwner],
      );
      const result = await settleMarketBatch(repository, instrument.product, batchId, batchGameDay, instrument.id);
      if (result.filled) {
        tradesCreated += Number(result.fillCount ?? 0);
        await repository.query(
          `UPDATE market_batch_instruments
              SET fill_count = fill_count + $3, volume_units = volume_units + $4, economic_transaction_id = $5,
                  clearing_price_units = $6
            WHERE batch_id = $1 AND instrument_id = $2 AND lease_owner = $7`,
          [batchId, instrument.id, Number(result.fillCount ?? 0), String(result.quantityUnits ?? 0), result.economicTransactionId ?? null, result.clearingPriceUnits ?? null, leaseOwner],
        );
      }
      await repository.query(
        `UPDATE market_batch_instruments
            SET status = 'completed', completed_at = CURRENT_TIMESTAMP, lease_owner = NULL, lease_expires_at = NULL,
                clearing_price_units = COALESCE(clearing_price_units, (SELECT last_clearing_price_units FROM market_instrument_state WHERE instrument_id = $2))
          WHERE batch_id = $1 AND instrument_id = $2 AND status = 'clearing' AND lease_owner = $4`,
        [batchId, instrument.id, instrument.product, leaseOwner],
      );
      const after = await rebuildMarketInstrumentState(repository, instrument.id);
      await refreshMarketPriceProjection(repository, instrument, after, batchGameDay);
      await refreshMarketCandles(repository, instrument.id, batchId);
    }
    if (!batchComplete) break;
    const completed = await repository.query(
      `UPDATE market_batches
          SET status = 'completed', completed_at = CURRENT_TIMESTAMP
        WHERE id = $1 AND status = 'clearing'
          AND NOT EXISTS (SELECT 1 FROM market_batch_instruments WHERE batch_id = $1 AND status <> 'completed')`,
      [batchId],
    );
    if (completed.rowCount !== 1) { busy = true; break; }
    batchesProcessed += 1;
  }
  if (features?.futures !== false && Date.now() - startedAt < workBudgetMs) settledFutures = await settleDueDeliveryFutures(repository, safeProcessedGameDay, workBudgetMs - (Date.now() - startedAt));
  return { batchesProcessed, tradesCreated, futuresSettled: settledFutures, busy };
}
