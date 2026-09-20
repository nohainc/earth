import type { Env } from './index.ts';
import { currentHuman } from './auth-session.ts';
import { withRepository, type PostgresRepository } from './repository.ts';
import { cancelMarketOrder, submitMarketOrder } from './market-postgres.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';
import { assertEconomyCaughtUp, isSettlementBarrierError, SettlementCatchupBarrierError } from './settlement-barrier-postgres.ts';
import { MARKET_ASSET_IDS } from './market-model.ts';
import { calculateFeeUnits, calculateQuoteUnits, displayPriceToUnits, displayQuantityToUnits, displayRateToBps, priceUnitsToDisplayPrice, unitsToDisplayQuantity } from './market-units.ts';
import { formatCreditUnits } from './money.ts';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation.ts';
import { featureDisabledResponse, featureEnabled } from './feature-config.ts';
import { marketFeeRate } from './market-rules.ts';
import { readHouseCommodityPositions } from './market-house-position-postgres.ts';
import type { MarketBook, MarketInstrumentSummary, MarketOrder, MarketQuote } from './types/market.dto.ts';
import { readMarketOrderRows, serializeMarketOrder } from './market-order-read-model.ts';

type InstrumentRow = {
  id: string;
  symbol: string;
  asset_id: number;
  quote_asset_id: number;
  status: string;
  base_code?: string;
  base_decimals?: number;
  quote_code?: string;
  quote_decimals?: number;
  genesis_reference_price_units?: string;
};

function instrumentPayload(row: InstrumentRow): MarketInstrumentSummary {
  return {
    id: String(row.id),
    symbol: row.symbol,
    instrumentType: 'SPOT',
    baseAsset: { id: String(row.asset_id), code: row.base_code ?? null, decimals: row.base_decimals ?? null },
    quoteAsset: { id: String(row.quote_asset_id), code: row.quote_code ?? null, decimals: row.quote_decimals ?? null },
    lotSize: '1',
    priceTick: priceUnitsToDisplayPrice('1'),
    status: row.status,
    rulesVersion: 'spot-market-v1',
    genesisReferencePrice: row.genesis_reference_price_units ? priceUnitsToDisplayPrice(row.genesis_reference_price_units) : null,
  };
}

async function findInstrument(repository: PostgresRepository, key: string): Promise<InstrumentRow | null> {
  const result = await repository.query<InstrumentRow>(
    `SELECT i.id, i.symbol, i.asset_id, i.quote_asset_id,
            i.status, i.genesis_reference_price_units::TEXT,
            ba.code AS base_code,
            qa.code AS quote_code
       FROM market_instruments i
       LEFT JOIN economic_assets ba ON ba.id = i.asset_id
       LEFT JOIN economic_assets qa ON qa.id = i.quote_asset_id
      WHERE (i.id::TEXT = $1 OR i.symbol = $1)
        AND i.status IN ('ACTIVE', 'HALTED', 'CLOSED', 'EXPIRED', 'SETTLED')
      LIMIT 1`, [key]);
  return result.rows[0] ?? null;
}

function unavailable(): Response {
  return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
}

function decodeOrderCursor(value: string | null): { createdAt: string; id: string } | null {
  if (!value) return null;
  try {
    const parsed = JSON.parse(atob(value)) as { createdAt?: string; id?: string };
    return parsed.createdAt && parsed.id ? { createdAt: parsed.createdAt, id: parsed.id } : null;
  } catch {
    throw new Error('Invalid market order cursor');
  }
}

function encodeOrderCursor(row: Record<string, unknown>): string | null {
  if (!row.created_at || !row.id) return null;
  return btoa(JSON.stringify({ createdAt: String(row.created_at), id: String(row.id) }));
}

async function readInstrumentRoute(repository: PostgresRepository, key: string, resource: string, url: URL): Promise<Record<string, unknown>> {
  const instrument = await findInstrument(repository, decodeURIComponent(key));
  if (!instrument) throw new Error('Market instrument not found');
  if (resource === 'book') {
    const [result, state] = await Promise.all([repository.query<Record<string, unknown>>(
      `SELECT o.id, o.instrument_id, i.symbol, o.side, o.status, o.quantity_units::TEXT, o.remaining_units::TEXT,
              o.limit_price_units::TEXT, o.rules_version, o.created_at
         FROM market_orders o JOIN market_instruments i ON i.id = o.instrument_id
        WHERE o.instrument_id = $1 AND o.status IN ('OPEN', 'PARTIAL')
        ORDER BY o.side, o.limit_price_units DESC, o.created_at ASC
        LIMIT 2000`, [instrument.id]), repository.query<Record<string, unknown>>(
      `SELECT last_clearing_price_units::TEXT, best_bid_units::TEXT, best_ask_units::TEXT,
              open_buy_units::TEXT, open_sell_units::TEXT, rolling_volume_units::TEXT
         FROM market_instrument_state WHERE instrument_id = $1`, [instrument.id])]);
    return {
      instrument: instrumentPayload(instrument),
      bids: result.rows.filter((row) => row.side === 'buy').map((row) => serializeMarketOrder(row)),
      asks: result.rows.filter((row) => row.side === 'sell').map((row) => serializeMarketOrder(row)),
      state: state.rows[0] ?? { last_clearing_price_units: null, best_bid_units: null, best_ask_units: null, open_buy_units: '0', open_sell_units: '0', rolling_volume_units: '0' },
    };
  }

  if (resource === 'batches') {
    const result = await repository.query<Record<string, unknown>>(
      `SELECT b.id, b.game_day, b.game_minute, b.status,
              COUNT(DISTINCT f.id)::INTEGER AS fill_count,
              COALESCE(SUM(f.quantity_units), 0)::TEXT AS volume_units,
              MAX(f.economic_transaction_id) AS economic_transaction_id
         FROM market_batches b
         LEFT JOIN market_fills f ON f.batch_id = b.id AND f.instrument_id = $1
        WHERE EXISTS (SELECT 1 FROM market_orders o WHERE o.batch_id = b.id AND o.instrument_id = $1)
        GROUP BY b.id, b.game_day, b.game_minute, b.status ORDER BY b.id DESC LIMIT 200`, [instrument.id]);
    return { instrument: instrumentPayload(instrument), batches: result.rows.map((row) => ({
      id: row.id, gameDay: row.game_day, gameMinute: row.game_minute, status: row.status,
      fillCount: row.fill_count, volume: unitsToDisplayQuantity(String(row.volume_units ?? '0')), economicTransactionId: row.economic_transaction_id,
    })) };
  }

  if (resource === 'projection') {
    const [state, stats] = await Promise.all([
      repository.query<Record<string, unknown>>(
        `SELECT last_clearing_price_units::TEXT, best_bid_units::TEXT, best_ask_units::TEXT,
                open_buy_units::TEXT, open_sell_units::TEXT, rolling_volume_units::TEXT
           FROM market_instrument_state WHERE instrument_id = $1`, [instrument.id]),
      repository.query<Record<string, unknown>>(
        `WITH recent AS (
          SELECT price_units::NUMERIC AS price_units, quantity_units::NUMERIC AS quantity_units
            FROM market_fills
           WHERE instrument_id = $1 AND batch_id IN (SELECT id FROM market_batches WHERE game_day >= (SELECT game_day - 7 FROM earth_get_current_game_time()))
        )
        SELECT COUNT(*)::INTEGER AS fill_count,
               COALESCE(SUM(quantity_units), 0)::TEXT AS volume_units,
               COALESCE(SUM(price_units * quantity_units) / NULLIF(SUM(quantity_units), 0), 0)::TEXT AS vwap_units,
               COALESCE(STDDEV_POP(price_units), 0)::TEXT AS volatility_units
          FROM recent`, [instrument.id]),
    ]);
    const current = state.rows[0] ?? {};
    const bestBid = current.best_bid_units === null || current.best_bid_units === undefined ? null : BigInt(String(current.best_bid_units));
    const bestAsk = current.best_ask_units === null || current.best_ask_units === undefined ? null : BigInt(String(current.best_ask_units));
    return {
      instrument: instrumentPayload(instrument),
      state: current,
      projection: {
        spreadUnits: bestBid !== null && bestAsk !== null && bestAsk >= bestBid ? (bestAsk - bestBid).toString() : null,
        sevenDay: stats.rows[0] ?? { fill_count: 0, volume_units: '0', vwap_units: '0', volatility_units: '0' },
        generatedFrom: 'postgres-canonical-facts',
      },
    };
  }

  if (resource === 'fills') {
    const result = await repository.query<Record<string, unknown>>(
      `SELECT id, batch_id, buy_order_id, sell_order_id, buyer_economic_id, seller_economic_id,
              quantity_units::TEXT, price_units::TEXT, gross_quote_units::TEXT,
              buyer_fee_units::TEXT, seller_fee_units::TEXT, economic_transaction_id,
              sequence_no
         FROM market_fills WHERE instrument_id = $1 ORDER BY id DESC LIMIT 500`, [instrument.id]);
    return { instrument: instrumentPayload(instrument), fills: result.rows.map((row) => ({
      id: row.id, batchId: row.batch_id, buyOrderId: row.buy_order_id, sellOrderId: row.sell_order_id,
      buyerEconomicId: row.buyer_economic_id, sellerEconomicId: row.seller_economic_id,
      quantity: unitsToDisplayQuantity(String(row.quantity_units ?? '0')), price: priceUnitsToDisplayPrice(String(row.price_units)),
      grossQuote: formatCreditUnits(BigInt(String(row.gross_quote_units ?? '0'))),
      buyerFee: formatCreditUnits(BigInt(String(row.buyer_fee_units ?? '0'))), sellerFee: formatCreditUnits(BigInt(String(row.seller_fee_units ?? '0'))),
      economicTransactionId: row.economic_transaction_id, sequenceNo: row.sequence_no,
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
    volume: unitsToDisplayQuantity(String(row.volume_units ?? '0')), fillCount: row.fill_count,
  })) };
}

export async function handleMarketApiRoutes(request: Request, env: Env, url: URL): Promise<Response | null> {
  const path = url.pathname;
  const instrumentsPath = path === '/api/market/instruments' && request.method === 'GET';
  const instrumentMatch = path.match(/^\/api\/market\/([^/]+)\/(book|batches|fills|candles)$/);
  const myOrders = path === '/api/market/orders/my' && request.method === 'GET';
  const housePositions = path === '/api/market/positions' && request.method === 'GET';
  const orderQuote = path === '/api/market/order-quote' && request.method === 'POST';
  const orderPost = path === '/api/market/orders' && request.method === 'POST';
  const cancelMatch = path.match(/^\/api\/market\/orders\/([^/]+)$/);
  if (!instrumentsPath && !instrumentMatch && !myOrders && !housePositions && !orderQuote && !orderPost && !(cancelMatch && request.method === 'DELETE')) return null;
  if ((orderPost || (cancelMatch && request.method === 'DELETE')) && !featureEnabled(env, 'spotMarket')) return featureDisabledResponse('spotMarket');

  try {
    if (instrumentsPath) {
      const result = await withRepository(env, (repository) => repository.query<InstrumentRow>(
        `SELECT i.id, i.symbol, i.asset_id, i.quote_asset_id,
                i.status, i.genesis_reference_price_units::TEXT, ba.code AS base_code,
                qa.code AS quote_code
           FROM market_instruments i LEFT JOIN economic_assets ba ON ba.id = i.asset_id
           LEFT JOIN economic_assets qa ON qa.id = i.quote_asset_id
          WHERE i.status IN ('ACTIVE', 'HALTED', 'CLOSED', 'EXPIRED', 'SETTLED') ORDER BY i.symbol`));
      if (!result) return unavailable();
      return Response.json({ instruments: result.rows.map(instrumentPayload), persistence: 'planetscale-postgres' });
    }

    const viewer = myOrders || housePositions || orderQuote || orderPost || cancelMatch ? await currentHuman(request, env) : null;
    if ((myOrders || housePositions || orderQuote || orderPost || cancelMatch) && !viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });

    if (instrumentMatch) {
      const result = await withRepository(env, (repository) => readInstrumentRoute(repository, instrumentMatch[1], instrumentMatch[2], url));
      if (!result) return unavailable();
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (myOrders) {
      const corpId = url.searchParams.get('corporationId')?.trim();
      const limit = Math.min(Math.max(Number(url.searchParams.get('limit') ?? 100) || 100, 1), 200);
      const cursor = decodeOrderCursor(url.searchParams.get('cursor'));
      const result = await withRepository(env, async (repository) => {
        const rows = corpId
          ? await readMarketOrderRows(repository, { ownerRegistryId: corpId, limit, beforeCreatedAt: cursor?.createdAt, beforeId: cursor?.id })
          : await readMarketOrderRows(repository, { ownerRegistryId: viewer!.house_id, limit, beforeCreatedAt: cursor?.createdAt, beforeId: cursor?.id });
        return {
          orders: rows.rows.map((row) => serializeMarketOrder(row)),
          nextCursor: rows.rows.length === limit ? encodeOrderCursor(rows.rows[rows.rows.length - 1]) : null,
        };
      });
      if (!result) return unavailable();
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (housePositions) {
      const result = await withRepository(env, (repository) =>
        readHouseCommodityPositions(repository, viewer!.house_id));
      if (!result) return unavailable();
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (orderQuote) {
      const parsed = await parseJsonBody<{ product?: string; quantity?: string; limitPrice?: string; side?: string; instrumentId?: string; corporationId?: string; ownerId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const product = body.product?.trim().toLowerCase() ?? '';
      const side = body.side === 'sell' ? 'sell' : 'buy';
      const quantity = body.quantity?.trim() ?? '';
      const limitPrice = body.limitPrice?.trim() ?? '';
      const corpId = body.corporationId || (body.ownerId?.startsWith('CORP-') ? body.ownerId : null);
      if (!product || !quantity || !limitPrice) {
        return Response.json({ ok: false, error: 'A positive product, quantity, and limit price are required' }, { status: 400 });
      }
      const result = await withRepository(env, async (repository) => {
        const instrument = body.instrumentId
          ? await findInstrument(repository, body.instrumentId)
          : await findInstrument(repository, `SPOT-${product.toUpperCase()}`);
        if (!instrument) throw new Error('Market instrument not found');
        const quantityUnits = displayQuantityToUnits(quantity);
        const priceUnits = displayPriceToUnits(limitPrice);
        const quoteUnits = calculateQuoteUnits(quantityUnits, priceUnits);
        const feeRate = side === 'buy' ? await marketFeeRate(repository, viewer!.id) : '0';
        const feeUnits = calculateFeeUnits(quoteUnits, feeRate);
        const housePosition = !corpId
          ? (await readHouseCommodityPositions(repository, viewer!.house_id)).positions
              .find((position) => position.product === product)
          : null;
        const clock = await readAuthoritativeGameTime(repository);
        const currentDay = clock.gameDay;
        const currentMinute = clock.gameMinute;
        const batchMinutes = 60;
        const nextMinute = Math.ceil((currentMinute + 1) / batchMinutes) * batchMinutes;
        return {
          ok: true,
          instrument: instrumentPayload(instrument),
          side, quantity: unitsToDisplayQuantity(quantityUnits), limitPrice: priceUnitsToDisplayPrice(priceUnits),
          baseValueUnits: quoteUnits.toString(), feeUnits: feeUnits.toString(), totalEscrowUnits: (quoteUnits + feeUnits).toString(),
          feeBps: String(displayRateToBps(feeRate)),
          availableQuantity: housePosition?.availableQuantity ?? null,
          reservedQuantity: housePosition?.reservedQuantity ?? null,
          currentQuantity: housePosition?.currentQuantity ?? null,
          nextClearing: {
            gameDay: currentDay + Math.floor(nextMinute / 1440),
            gameMinute: nextMinute % 1440,
            intervalMinutes: batchMinutes,
            schedule: 'server-scheduled-market-batch',
          },
          generatedFrom: 'postgres-canonical-facts',
        };
      });
      if (!result) return unavailable();
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (orderPost) {
      const parsed = await parseJsonBody<{ product?: string; quantity?: string; limitPrice?: string; side?: string; correlationId?: string; instrumentId?: string; corporationId?: string; ownerId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const product = body.product?.trim().toLowerCase() ?? '';
      const side = body.side === 'sell' ? 'sell' : 'buy';
      const quantity = body.quantity?.trim() ?? '';
      const limitPrice = body.limitPrice?.trim() ?? '';
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!product || !quantity || !limitPrice || !correlationId) {
        return Response.json({ ok: false, error: 'Invalid market order' }, { status: 400 });
      }
      const result = await withRepository(env, async (repository) => {
        await assertEconomyCaughtUp(repository);
        return submitMarketOrder(repository, { humanId: viewer!.id, product, side, quantity, limitPrice, correlationId, instrumentId: body.instrumentId, corporationId: body.corporationId, ownerId: body.ownerId });
      });
      if (!result) return unavailable();
      const order = result.order && typeof result.order === 'object'
        ? await withRepository(env, async (repository) => {
            const rows = await readMarketOrderRows(repository, { orderId: String((result.order as Record<string, unknown>).id ?? '') });
            return rows.rows[0] ? serializeMarketOrder(rows.rows[0]) : null;
          })
        : result.order;
      return Response.json({ ...result, order, persistence: 'planetscale-postgres' });
    }
    if (cancelMatch) {
      const result = await withRepository(env, (repository) => cancelMarketOrder(repository, { orderId: decodeURIComponent(cancelMatch[1]), humanId: viewer!.id }));
      if (!result) return unavailable();
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
  } catch (error) {
    if (isSettlementBarrierError(error)) {
      return error.toResponse();
    }
    const message = error instanceof Error ? error.message : 'Market request failed';
    return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 400 });
  }
  return null;
}
