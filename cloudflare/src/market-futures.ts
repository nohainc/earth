import type { PostgresRepository } from './repository.ts';
import { cancelMarketOrder, submitMarketOrder } from './market-postgres.ts';
import { MARKET_ASSET_IDS } from './market-model.ts';
import { absoluteGameMinute, gamePosition } from './market-time.ts';

type FutureInput = {
  humanId: string;
  commodity: string;
  size: number;
  strikePrice: number;
  durationGameMinutes: number;
  correlationId: string;
};

const FUTURE_ASSETS: Record<string, number> = {
  material: MARKET_ASSET_IDS.MATERIAL,
  components: MARKET_ASSET_IDS.COMPONENTS,
  energy: MARKET_ASSET_IDS.ENERGY,
  compute: MARKET_ASSET_IDS.COMPUTE,
  food: MARKET_ASSET_IDS.FOOD,
};

async function createOrGetFutureInstrument(repository: PostgresRepository, input: FutureInput): Promise<{ id: string; symbol: string; expiry: number }> {
  const commodity = input.commodity.toLowerCase().trim();
  const assetId = FUTURE_ASSETS[commodity];
  if (!assetId) throw new Error(`Invalid future commodity '${input.commodity}'`);
  const world = await repository.query<{ game_day: number; game_minute: number }>("SELECT game_day, game_minute FROM world_state WHERE id = 'WORLD'");
  const now = absoluteGameMinute(Number(world.rows[0]?.game_day ?? 1), Number(world.rows[0]?.game_minute ?? 0));
  const expiry = now + input.durationGameMinutes;
  const expiryDay = gamePosition(expiry).gameDay;
  const symbol = `${commodity.toUpperCase()}-FUT-D${expiryDay}`;
  const instrument = await repository.query<{ id: string; symbol: string; expiry_total_game_minute: string }>(
    `INSERT INTO market_instruments
      (id, symbol, instrument_type, base_asset_id, quote_asset_id, expiry_total_game_minute, lot_size_units, price_tick_units, status, rules_version)
     VALUES ($1,$2,'DELIVERY_FUTURE',$3,${MARKET_ASSET_IDS.CREDIT},$4,$5,$6,'active','market-v2')
     ON CONFLICT (symbol) DO UPDATE SET updated_at = CURRENT_TIMESTAMP
     RETURNING id, symbol, expiry_total_game_minute`,
    [`FUT-${commodity.toUpperCase()}-${expiry}`, symbol, assetId, expiry, 1, 1],
  );
  const row = instrument.rows[0];
  if (!row) throw new Error('Unable to create delivery-future instrument');
  if (Number(row.expiry_total_game_minute) !== expiry) throw new Error('A future with this expiry symbol already has a different expiry');
  return { id: row.id, symbol: row.symbol, expiry };
}

export async function createDeliveryFutureListing(repository: PostgresRepository, input: FutureInput): Promise<Record<string, unknown>> {
  if (!Number.isFinite(input.size) || input.size <= 0) throw new Error('Contract size must be greater than 0');
  if (!Number.isFinite(input.strikePrice) || input.strikePrice <= 0) throw new Error('Strike price must be greater than 0');
  if (!Number.isInteger(input.durationGameMinutes) || input.durationGameMinutes < 1) throw new Error('Duration must be a positive whole number of game minutes');
  const instrument = await repository.transaction((tx) => createOrGetFutureInstrument(tx, input));
  const order = await submitMarketOrder(repository, {
    humanId: input.humanId,
    product: input.commodity.toLowerCase().trim(),
    side: 'sell',
    quantity: input.size,
    limitPrice: input.strikePrice,
    correlationId: input.correlationId,
    instrumentId: instrument.id,
  });
  return { ok: true, instrumentId: instrument.id, symbol: instrument.symbol, expiryTotalGameMinute: instrument.expiry, order: order.order };
}

export async function submitDeliveryFutureBuy(repository: PostgresRepository, input: { humanId: string; orderId: string; correlationId: string }): Promise<Record<string, unknown>> {
  const result = await repository.query<{ product: string; instrument_id: string; quantity_units: string; limit_price_units: string }>(
    `SELECT o.product, o.instrument_id,
            o.quantity_units - o.filled_quantity_units AS quantity_units,
            o.limit_price_units
       FROM market_orders o JOIN market_instruments i ON i.id = o.instrument_id
      WHERE o.id = $1 AND o.side = 'sell' AND o.status IN ('open', 'partial')
        AND o.quantity_units > o.filled_quantity_units
        AND i.instrument_type = 'DELIVERY_FUTURE' AND i.status = 'active'`,
    [input.orderId],
  );
  const listing = result.rows[0];
  if (!listing) throw new Error('Delivery-future listing not found');
  return submitMarketOrder(repository, {
    humanId: input.humanId,
    product: listing.product,
    side: 'buy',
    quantity: Number(listing.quantity_units) / 1_000_000,
    limitPrice: Number(listing.limit_price_units) / 100,
    correlationId: input.correlationId,
    instrumentId: listing.instrument_id,
  });
}

export async function cancelDeliveryFutureListing(repository: PostgresRepository, input: { humanId: string; orderId: string }): Promise<Record<string, unknown>> {
  const result = await repository.query(
    `SELECT 1
       FROM market_orders o JOIN market_instruments i ON i.id = o.instrument_id
      WHERE o.id = $1 AND o.side = 'sell' AND i.instrument_type = 'DELIVERY_FUTURE'`,
    [input.orderId],
  );
  if (!result.rows[0]) throw new Error('Delivery-future listing not found');
  return cancelMarketOrder(repository, { humanId: input.humanId, orderId: input.orderId });
}
