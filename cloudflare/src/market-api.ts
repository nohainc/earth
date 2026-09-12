import type { Env } from './index.ts';
import { currentHuman } from './auth-session.ts';
import { withRepository, type PostgresRepository } from './repository.ts';
import { cancelMarketOrder, submitMarketOrder } from './market-postgres.ts';
import { assetUnitScale, MARKET_ASSET_IDS } from './market-model.ts';
import { priceUnitsToDisplayPrice, unitsToDisplayQuantity } from './market-units.ts';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation.ts';
import { featureDisabledResponse, featureEnabled } from './feature-config.ts';

type InstrumentRow = {
  id: string;
  symbol: string;
  instrument_type: string;
  base_asset_id: number;
  quote_asset_id: number;
  lot_size_units: string;
  price_tick_units: string;
  status: string;
  rules_version: string;
  base_code?: string;
  base_decimals?: number;
  quote_code?: string;
  quote_decimals?: number;
};

function numberUnits(value: unknown, scale: number): number {
  return Number(BigInt(String(value ?? 0))) / scale;
}

function instrumentPayload(row: InstrumentRow): Record<string, unknown> {
  return {
    id: row.id,
    symbol: row.symbol,
    instrumentType: row.instrument_type,
    baseAsset: { id: row.base_asset_id, code: row.base_code ?? null, decimals: row.base_decimals ?? null },
    quoteAsset: { id: row.quote_asset_id, code: row.quote_code ?? null, decimals: row.quote_decimals ?? null },
    lotSize: numberUnits(row.lot_size_units, assetUnitScale(row.base_asset_id)),
    priceTick: priceUnitsToDisplayPrice(row.price_tick_units),
    status: row.status,
    rulesVersion: row.rules_version,
  };
}

async function findInstrument(repository: PostgresRepository, key: string): Promise<InstrumentRow | null> {
  const result = await repository.query<InstrumentRow>(
    `SELECT i.id, i.symbol, i.instrument_type, i.base_asset_id, i.quote_asset_id,
            i.lot_size_units::TEXT, i.price_tick_units::TEXT,
            i.status, i.rules_version,
            ba.code AS base_code, ba.decimals AS base_decimals,
            qa.code AS quote_code, qa.decimals AS quote_decimals
       FROM market_instruments i
       LEFT JOIN economic_assets ba ON ba.id = i.base_asset_id
       LEFT JOIN economic_assets qa ON qa.id = i.quote_asset_id
      WHERE (i.id::TEXT = $1 OR i.symbol = $1)
        AND i.instrument_type = 'SPOT'
        AND i.status IN ('active', 'halted', 'closed', 'expired', 'settled')
      LIMIT 1`, [key]);
  return result.rows[0] ?? null;
}

function serializeOrder(row: Record<string, unknown>, baseAssetId = Number(row.base_asset_id ?? row.asset_id ?? MARKET_ASSET_IDS.MATERIAL)): Record<string, unknown> {
  const quantity = BigInt(String(row.quantity_units ?? 0));
  const filled = BigInt(String(row.filled_quantity_units ?? row.filled_units ?? 0));
  const remaining = quantity - filled;
  return {
    id: row.id,
    instrumentId: row.instrument_id,
    product: row.product,
    side: row.side,
    status: row.status,
    quantity: numberUnits(quantity, assetUnitScale(baseAssetId)),
    filledQuantity: numberUnits(filled, assetUnitScale(baseAssetId)),
    remainingQuantity: numberUnits(remaining, assetUnitScale(baseAssetId)),
    limitPrice: priceUnitsToDisplayPrice(String(row.limit_price_units ?? 0)),
    eligibleBatchId: row.eligible_batch_id,
    sequenceNo: row.sequence_no,
    buyerFeeBps: row.buyer_fee_bps,
    sellerFeeBps: row.seller_fee_bps,
    rulesVersion: row.rules_version,
    submittedGameDay: row.submitted_game_day,
    submittedGameMinute: row.submitted_game_minute,
    createdAt: row.created_at,
  };
}

function unavailable(): Response {
  return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
}

async function readInstrumentRoute(repository: PostgresRepository, key: string, resource: string, url: URL): Promise<Record<string, unknown>> {
  const instrument = await findInstrument(repository, decodeURIComponent(key));
  if (!instrument) throw new Error('Market instrument not found');
  const baseScale = assetUnitScale(instrument.base_asset_id);

  if (resource === 'book') {
    const result = await repository.query<Record<string, unknown>>(
      `SELECT id, side, status, quantity_units::TEXT, filled_quantity_units::TEXT,
              limit_price_units::TEXT, eligible_batch_id, sequence_no, rules_version, created_at
         FROM market_orders
        WHERE instrument_id = $1 AND status IN ('open', 'partial')
        ORDER BY side, limit_price_units DESC, sequence_no ASC
        LIMIT 2000`, [instrument.id]);
    return {
      instrument: instrumentPayload(instrument),
      bids: result.rows.filter((row) => row.side === 'buy').map((row) => serializeOrder(row, baseScale === 100 ? instrument.base_asset_id : instrument.base_asset_id)),
      asks: result.rows.filter((row) => row.side === 'sell').map((row) => serializeOrder(row, instrument.base_asset_id)),
    };
  }

  if (resource === 'batches') {
    const result = await repository.query<Record<string, unknown>>(
      `SELECT b.id, b.start_total_game_minute, b.end_total_game_minute, b.status AS batch_status,
              bi.status, bi.eligible_order_count, bi.fill_count, bi.volume_units::TEXT,
              bi.previous_price_units::TEXT, bi.clearing_price_units::TEXT,
              bi.economic_transaction_id, bi.started_at, bi.completed_at, bi.error_message
         FROM market_batches b JOIN market_batch_instruments bi ON bi.batch_id = b.id
        WHERE bi.instrument_id = $1 ORDER BY b.id DESC LIMIT 200`, [instrument.id]);
    return { instrument: instrumentPayload(instrument), batches: result.rows.map((row) => ({
      id: row.id, startTotalGameMinute: row.start_total_game_minute, endTotalGameMinute: row.end_total_game_minute,
      status: row.status ?? row.batch_status, eligibleOrderCount: row.eligible_order_count, fillCount: row.fill_count,
      volume: numberUnits(row.volume_units, baseScale), previousPrice: row.previous_price_units == null ? null : priceUnitsToDisplayPrice(String(row.previous_price_units)),
      clearingPrice: row.clearing_price_units == null ? null : priceUnitsToDisplayPrice(String(row.clearing_price_units)),
      economicTransactionId: row.economic_transaction_id, startedAt: row.started_at, completedAt: row.completed_at, error: row.error_message,
    })) };
  }

  if (resource === 'fills') {
    const result = await repository.query<Record<string, unknown>>(
      `SELECT id, batch_id, buy_order_id, sell_order_id, buyer_economic_id, seller_economic_id,
              quantity_units::TEXT, price_units::TEXT, gross_quote_units::TEXT,
              buyer_fee_units::TEXT, seller_fee_units::TEXT, economic_transaction_id,
              sequence_no, game_day, game_minute, created_at
         FROM market_fills WHERE instrument_id = $1 ORDER BY id DESC LIMIT 500`, [instrument.id]);
    return { instrument: instrumentPayload(instrument), fills: result.rows.map((row) => ({
      id: row.id, batchId: row.batch_id, buyOrderId: row.buy_order_id, sellOrderId: row.sell_order_id,
      buyerEconomicId: row.buyer_economic_id, sellerEconomicId: row.seller_economic_id,
      quantity: numberUnits(row.quantity_units, baseScale), price: priceUnitsToDisplayPrice(String(row.price_units)),
      grossQuote: numberUnits(row.gross_quote_units, assetUnitScale(instrument.quote_asset_id)),
      buyerFee: numberUnits(row.buyer_fee_units, assetUnitScale(instrument.quote_asset_id)), sellerFee: numberUnits(row.seller_fee_units, assetUnitScale(instrument.quote_asset_id)),
      economicTransactionId: row.economic_transaction_id, sequenceNo: row.sequence_no, gameDay: row.game_day, gameMinute: row.game_minute, createdAt: row.created_at,
    })) };
  }

  const interval = url.searchParams.get('interval') === 'daily' ? 'daily' : 'hourly';
  const result = await repository.query<Record<string, unknown>>(
    `SELECT period_id, open_price_units::TEXT, high_price_units::TEXT, low_price_units::TEXT,
            close_price_units::TEXT, volume_units::TEXT, fill_count
       FROM market_candles WHERE instrument_id = $1 AND interval_kind = $2
      ORDER BY period_id DESC LIMIT 500`, [instrument.id, interval]);
  return { instrument: instrumentPayload(instrument), interval, candles: result.rows.map((row) => ({
    periodId: row.period_id, open: priceUnitsToDisplayPrice(String(row.open_price_units)), high: priceUnitsToDisplayPrice(String(row.high_price_units)),
    low: priceUnitsToDisplayPrice(String(row.low_price_units)), close: priceUnitsToDisplayPrice(String(row.close_price_units)),
    volume: numberUnits(row.volume_units, baseScale), fillCount: row.fill_count,
  })) };
}

export async function handleMarketApiRoutes(request: Request, env: Env, url: URL): Promise<Response | null> {
  const path = url.pathname;
  const instrumentsPath = path === '/api/market/instruments' && request.method === 'GET';
  const instrumentMatch = path.match(/^\/api\/market\/([^/]+)\/(book|batches|fills|candles)$/);
  const myOrders = path === '/api/market/orders/my' && request.method === 'GET';
  const orderPost = path === '/api/market/orders' && request.method === 'POST';
  const cancelMatch = path.match(/^\/api\/market\/orders\/([^/]+)$/);
  if (!instrumentsPath && !instrumentMatch && !myOrders && !orderPost && !(cancelMatch && request.method === 'DELETE')) return null;
  if ((orderPost || (cancelMatch && request.method === 'DELETE')) && !featureEnabled(env, 'spotMarket')) return featureDisabledResponse('spotMarket');

  try {
    if (instrumentsPath) {
      const result = await withRepository(env, (repository) => repository.query<InstrumentRow>(
        `SELECT i.id, i.symbol, i.instrument_type, i.base_asset_id, i.quote_asset_id,
                i.lot_size_units::TEXT, i.price_tick_units::TEXT,
                i.status, i.rules_version, ba.code AS base_code, ba.decimals AS base_decimals,
                qa.code AS quote_code, qa.decimals AS quote_decimals
           FROM market_instruments i LEFT JOIN economic_assets ba ON ba.id = i.base_asset_id
           LEFT JOIN economic_assets qa ON qa.id = i.quote_asset_id
          WHERE i.instrument_type = 'SPOT'
            AND i.status IN ('active', 'halted', 'closed', 'expired', 'settled') ORDER BY i.symbol`));
      if (!result) return unavailable();
      return Response.json({ instruments: result.rows.map(instrumentPayload), persistence: 'planetscale-postgres' });
    }

    const viewer = myOrders || orderPost || cancelMatch ? await currentHuman(request, env) : null;
    if ((myOrders || orderPost || cancelMatch) && !viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });

    if (instrumentMatch) {
      const result = await withRepository(env, (repository) => readInstrumentRoute(repository, instrumentMatch[1], instrumentMatch[2], url));
      if (!result) return unavailable();
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (myOrders) {
      const result = await withRepository(env, async (repository) => {
        const rows = await repository.query<Record<string, unknown>>(
          `SELECT market_orders.*
             FROM market_orders
             JOIN owner_registry owner ON owner.economic_id = market_orders.owner_economic_id
            WHERE owner.id = (SELECT house_id FROM humans WHERE id = $1)
            ORDER BY market_orders.created_at DESC LIMIT 500`, [viewer!.id]);
        return { orders: rows.rows.map((row) => serializeOrder(row, Number(row.instrument_base_asset_id ?? row.base_asset_id ?? MARKET_ASSET_IDS.MATERIAL))) };
      });
      if (!result) return unavailable();
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (orderPost) {
      const parsed = await parseJsonBody<{ product?: string; quantity?: number; limitPrice?: number; side?: string; correlationId?: string; instrumentId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const product = body.product?.trim().toLowerCase() ?? '';
      const side = body.side === 'sell' ? 'sell' : 'buy';
      const quantity = Number(body.quantity);
      const limitPrice = Number(body.limitPrice);
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!product || !Number.isFinite(quantity) || quantity <= 0 || !Number.isFinite(limitPrice) || limitPrice <= 0 || !correlationId) {
        return Response.json({ ok: false, error: 'Invalid market order' }, { status: 400 });
      }
      const result = await withRepository(env, (repository) => submitMarketOrder(repository, { humanId: viewer!.id, product, side, quantity, limitPrice, correlationId, instrumentId: body.instrumentId }));
      if (!result) return unavailable();
      const order = result.order && typeof result.order === 'object' ? serializeOrder(result.order as Record<string, unknown>) : result.order;
      return Response.json({ ...result, order, persistence: 'planetscale-postgres' });
    }
    if (cancelMatch) {
      const result = await withRepository(env, (repository) => cancelMarketOrder(repository, { orderId: decodeURIComponent(cancelMatch[1]), humanId: viewer!.id }));
      if (!result) return unavailable();
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Market request failed';
    return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 400 });
  }
  return null;
}
