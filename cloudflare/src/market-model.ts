import type { PostgresRepository } from './repository.ts';

export const MARKET_BATCH_GAME_MINUTES = 60;

export const MARKET_ASSET_IDS = {
  CREDIT: 1,
  MATERIAL: 2,
  COMPONENTS: 3,
  ENERGY: 4,
  COMPUTE: 5,
  FOOD: 6,
} as const;

export const MARKET_ASSET_UNITS = {
  CREDIT: 100,
  MATERIAL: 1_000_000,
  COMPONENTS: 1_000_000,
  ENERGY: 1_000_000,
  COMPUTE: 1_000_000,
  FOOD: 1_000_000,
} as const;

export function assetUnitScale(assetId: number): number {
  switch (assetId) {
    case MARKET_ASSET_IDS.CREDIT: return MARKET_ASSET_UNITS.CREDIT;
    case MARKET_ASSET_IDS.MATERIAL: return MARKET_ASSET_UNITS.MATERIAL;
    case MARKET_ASSET_IDS.COMPONENTS: return MARKET_ASSET_UNITS.COMPONENTS;
    case MARKET_ASSET_IDS.ENERGY: return MARKET_ASSET_UNITS.ENERGY;
    case MARKET_ASSET_IDS.COMPUTE: return MARKET_ASSET_UNITS.COMPUTE;
    case MARKET_ASSET_IDS.FOOD: return MARKET_ASSET_UNITS.FOOD;
    default: throw new Error(`Unknown economic asset ${assetId}`);
  }
}

export type MarketInstrument = {
  id: string;
  symbol: string;
  instrument_type: 'SPOT';
  base_asset_id: number;
  quote_asset_id: number;
  lot_size_units: string;
  price_tick_units: string;
  status: string;
  rules_version: string;
};

export function spotInstrumentSymbol(product: string): string {
  return `SPOT-${product.trim().toUpperCase()}`;
}

export async function getActiveSpotInstrument(repo: PostgresRepository, product: string): Promise<MarketInstrument | null> {
  const result = await repo.query<MarketInstrument>(
    `SELECT id, symbol, instrument_type, base_asset_id, quote_asset_id,
            lot_size_units, price_tick_units, status, rules_version
       FROM market_instruments
      WHERE symbol = $1 AND instrument_type = 'SPOT' AND status = 'active'`,
    [spotInstrumentSymbol(product)],
  );
  return result.rows[0] ?? null;
}

export async function getActiveMarketInstrument(repo: PostgresRepository, instrumentId: string): Promise<MarketInstrument | null> {
  const result = await repo.query<MarketInstrument>(
    `SELECT id, symbol, instrument_type, base_asset_id, quote_asset_id,
            lot_size_units, price_tick_units, status, rules_version
       FROM market_instruments WHERE id = $1 AND instrument_type = 'SPOT' AND status = 'active'`,
    [instrumentId],
  );
  return result.rows[0] ?? null;
}

export async function listActiveSpotProducts(repo: PostgresRepository): Promise<string[]> {
  return (await listActiveSpotInstruments(repo)).map((instrument) => instrument.product);
}

export async function listActiveSpotInstruments(repo: PostgresRepository): Promise<Array<{ id: string; product: string }>> {
  const result = await repo.query<{ id: string; product: string }>(
    `SELECT id, lower(regexp_replace(symbol, '^SPOT-', '')) AS product
       FROM market_instruments
      WHERE instrument_type = 'SPOT' AND status = 'active'
      ORDER BY id`,
  );
  return result.rows;
}

export async function listActiveMarketInstruments(repo: PostgresRepository): Promise<Array<{ id: string; product: string; instrument_type: MarketInstrument['instrument_type']; rules_version: string }>> {
  const result = await repo.query<{ id: string; product: string; instrument_type: MarketInstrument['instrument_type']; rules_version: string }>(
    `SELECT id, lower(regexp_replace(symbol, '^SPOT-', '')) AS product, instrument_type, rules_version
       FROM market_instruments
      WHERE instrument_type = 'SPOT' AND status = 'active'
      ORDER BY id`,
  );
  return result.rows;
}
