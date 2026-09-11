import type { PostgresRepository } from './repository.ts';
import { assetUnitScale } from './market-model.ts';

export interface OHLCSnapshot {
  id: string;
  commodity: string;
  game_day: number;
  open_price: number;
  high_price: number;
  low_price: number;
  close_price: number;
  volume: number;
}

export interface FuturesContract {
  id: string;
  seller_human_id: string;
  buyer_human_id: string | null;
  commodity: string;
  contract_size: number;
  strike_price: number;
  expiry_game_day: number;
  collateral_locked: number;
  premium_paid: number;
  status: string;
  created_at: string;
}

/** Read-only V2 derivatives projection. Mutations live in market-futures.ts. */
export async function listCommodityDerivativesAndOHLC(
  repository: PostgresRepository,
  commodity = 'energy',
  humanId = 'H-0044',
) {
  const normalized = commodity.toLowerCase().trim();
  const instruments = await repository.query<{ id: string; base_asset_id: number }>(
    `SELECT id, base_asset_id
       FROM market_instruments
      WHERE symbol LIKE $1 AND instrument_type = 'DELIVERY_FUTURE'
      ORDER BY expiry_total_game_minute ASC
      LIMIT 1`,
    [`${normalized.toUpperCase()}-FUT-%`],
  );
  const assetId = Number(instruments.rows[0]?.base_asset_id ?? 0);
  const scale = assetId ? assetUnitScale(assetId) : 1_000_000;
  const [candles, orders, positions] = await Promise.all([
    repository.query(
      `SELECT c.instrument_id AS id, c.period_id AS game_day,
              c.open_price_units, c.high_price_units, c.low_price_units,
              c.close_price_units, c.volume_units
         FROM market_candles c
         JOIN market_instruments i ON i.id = c.instrument_id
        WHERE i.instrument_type = 'DELIVERY_FUTURE' AND i.base_asset_id = $1
          AND c.interval_kind = 'daily'
        ORDER BY c.period_id ASC LIMIT 50`, [assetId],
    ),
    repository.query(
      `SELECT o.id, o.human_id AS seller_human_id, NULL::TEXT AS buyer_human_id,
              o.product AS commodity, o.quantity_units - o.filled_units AS contract_size_units,
              o.limit_price_units AS strike_price_units,
              FLOOR(i.expiry_total_game_minute / 1440.0)::BIGINT AS expiry_game_day,
              o.reserved_base_units AS collateral_locked_units, 0::BIGINT AS premium_paid_units,
              o.status, o.created_at
         FROM market_orders o JOIN market_instruments i ON i.id = o.instrument_id
        WHERE i.instrument_type = 'DELIVERY_FUTURE' AND i.base_asset_id = $1
          AND o.side = 'sell' AND o.status IN ('open', 'partial')
        ORDER BY o.limit_price_units ASC, o.sequence_no ASC LIMIT 50`, [assetId],
    ),
    repository.query(
      `SELECT d.id, NULL::TEXT AS seller_human_id, $2::TEXT AS buyer_human_id,
              i.symbol AS commodity, d.quantity_units AS contract_size_units,
              d.delivery_price_units AS strike_price_units,
              FLOOR(d.expiry_total_game_minute / 1440.0)::BIGINT AS expiry_game_day,
              d.quantity_units AS collateral_locked_units,
              d.quantity_units * d.delivery_price_units / 1000000 AS premium_paid_units,
              d.status, d.created_at
         FROM derivative_obligations d JOIN market_instruments i ON i.id = d.instrument_id
        WHERE i.base_asset_id = $1
          AND (d.long_owner_economic_id = (SELECT economic_id FROM owner_registry WHERE id = COALESCE((SELECT house_id FROM humans WHERE id = $2), $2))
            OR d.short_owner_economic_id = (SELECT economic_id FROM owner_registry WHERE id = COALESCE((SELECT house_id FROM humans WHERE id = $2), $2)))
        ORDER BY expiry_game_day ASC, d.created_at DESC LIMIT 50`, [assetId, humanId],
    ),
  ]);
  const ohlc = candles.rows.map((row: any) => ({
    id: String(row.id), commodity: normalized, game_day: Number(row.game_day),
    open_price: Number(row.open_price_units) / 100, high_price: Number(row.high_price_units) / 100,
    low_price: Number(row.low_price_units) / 100, close_price: Number(row.close_price_units) / 100,
    volume: Number(row.volume_units) / scale,
  }));
  const closes = ohlc.map((row) => row.close_price);
  const movingAverage = (window: number) => closes.map((_, index) => index + 1 < window ? null : Math.round(closes.slice(index + 1 - window, index + 1).reduce((sum, value) => sum + value, 0) / window * 100) / 100);
  const mapContract = (row: any): FuturesContract => ({
    id: String(row.id), seller_human_id: row.seller_human_id ? String(row.seller_human_id) : '', buyer_human_id: row.buyer_human_id ? String(row.buyer_human_id) : null,
    commodity: normalized, contract_size: Number(row.contract_size_units) / scale,
    strike_price: Number(row.strike_price_units) / 100, expiry_game_day: Number(row.expiry_game_day),
    collateral_locked: Number(row.collateral_locked_units) / scale, premium_paid: Number(row.premium_paid_units) / 100,
    status: String(row.status), created_at: String(row.created_at),
  });
  return { ok: true, commodity: normalized, ohlc, ma7: movingAverage(7), ma25: movingAverage(25), orderbook: orders.rows.map(mapContract), userPositions: positions.rows.map(mapContract) };
}
