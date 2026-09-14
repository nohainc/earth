import type { PostgresRepository } from './repository.ts';

type Asset = { id: number; code: string };
type Flow = { production: string; consumption: string; transfer_in: string; transfer_out: string; net: string };

const ZERO = { production: '0', consumption: '0', transfer_in: '0', transfer_out: '0', net: '0' };

async function flow(tx: PostgresRepository, day: number, assetId: number, owner?: string): Promise<Flow> {
  const result = await tx.query<Flow>(
    `SELECT COALESCE(SUM(CASE WHEN t.transaction_kind = 'RESOURCE_PRODUCTION' AND e.delta_units > 0 THEN e.delta_units ELSE 0 END),0)::TEXT production,
            COALESCE(SUM(CASE WHEN t.transaction_kind = 'RESOURCE_CONSUMPTION' AND e.delta_units < 0 THEN ABS(e.delta_units) ELSE 0 END),0)::TEXT consumption,
            COALESCE(SUM(CASE WHEN t.transaction_kind = 'ASSET_TRANSFER' AND e.delta_units > 0 THEN e.delta_units ELSE 0 END),0)::TEXT transfer_in,
            COALESCE(SUM(CASE WHEN t.transaction_kind = 'ASSET_TRANSFER' AND e.delta_units < 0 THEN ABS(e.delta_units) ELSE 0 END),0)::TEXT transfer_out,
            COALESCE(SUM(e.delta_units),0)::TEXT net
       FROM economic_entries e JOIN economic_transactions t ON t.id=e.transaction_id
       JOIN economic_accounts a ON a.id=e.account_id
      WHERE t.game_day=$1 AND e.asset_id=$2 AND a.account_type='INVENTORY'
        AND ($3::TEXT IS NULL OR a.owner_economic_id=$3)`, [day, assetId, owner ?? null]);
  return result.rows[0] ?? ZERO;
}

async function shortage(tx: PostgresRepository, day: number, house?: string, assetCode?: string): Promise<string> {
  if (assetCode === 'FOOD') {
    const result = await tx.query<{ total: string }>(
      `SELECT COALESCE(SUM(m.food_shortfall_units),0)::TEXT total FROM personal_life_maintenance m
       WHERE m.game_day=$1 AND ($2::TEXT IS NULL OR m.house_id=(SELECT id FROM owner_registry WHERE economic_id=$2))`, [day, house ?? null]);
    return result.rows[0]?.total ?? '0';
  }
  const result = await tx.query<{ total: string }>(
    `SELECT COALESCE(SUM((j.shortage_units ->> $3)::BIGINT),0)::TEXT total FROM building_settlement_journals j
     WHERE j.game_day=$1 AND ($2::TEXT IS NULL OR j.house_economic_id=$2)`, [day, house ?? null, assetCode ?? '']);
  return result.rows[0]?.total ?? '0';
}

async function market(tx: PostgresRepository, day: number, assetId: number): Promise<{ volume: string; price: string | null }> {
  const result = await tx.query<{ volume: string; price: string | null }>(
    `SELECT COALESCE(SUM(f.quantity_units),0)::TEXT volume,
            CASE WHEN SUM(f.quantity_units)>0 THEN (SUM(f.quantity_units*f.price_units)/SUM(f.quantity_units))::BIGINT::TEXT ELSE NULL END price
       FROM market_fills f JOIN market_batches b ON b.id=f.batch_id JOIN market_instruments i ON i.id=f.instrument_id
      WHERE b.game_day=$1 AND i.asset_id=$2`, [day, assetId]);
  return result.rows[0] ?? { volume: '0', price: null };
}

export async function refreshResourceAnalyticsInTransaction(tx: PostgresRepository, day: number): Promise<void> {
  const assets = (await tx.query<Asset>(`SELECT id, code FROM economic_assets WHERE asset_kind='RESOURCE' ORDER BY id`)).rows;
  const houses = (await tx.query<{ economic_id: string }>(`SELECT economic_id FROM owner_registry WHERE owner_type='HOUSE'`)).rows;
  for (const asset of assets) {
    const f = await flow(tx, day, asset.id);
    const closing = await tx.query<{ balance: string }>(`SELECT COALESCE(SUM(balance_units),0)::TEXT balance FROM economic_accounts a JOIN owner_registry o ON o.economic_id=a.owner_economic_id WHERE o.owner_type='HOUSE' AND a.asset_id=$1 AND a.account_type='INVENTORY' AND a.status='ACTIVE'`, [asset.id]);
    const close = BigInt(closing.rows[0]?.balance ?? '0');
    const net = BigInt(f.net);
    const m = await market(tx, day, asset.id);
    const short = await shortage(tx, day, undefined, asset.code);
    await tx.query(`INSERT INTO global_resource_daily_state (game_day,asset_id,opening_balance_units,production_units,consumption_units,transfer_in_units,transfer_out_units,closing_balance_units,market_volume_units,average_price_units,shortage_units) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) ON CONFLICT (game_day,asset_id) DO UPDATE SET opening_balance_units=EXCLUDED.opening_balance_units,production_units=EXCLUDED.production_units,consumption_units=EXCLUDED.consumption_units,transfer_in_units=EXCLUDED.transfer_in_units,transfer_out_units=EXCLUDED.transfer_out_units,closing_balance_units=EXCLUDED.closing_balance_units,market_volume_units=EXCLUDED.market_volume_units,average_price_units=EXCLUDED.average_price_units,shortage_units=EXCLUDED.shortage_units`, [day, asset.id, (close-net).toString(), f.production, f.consumption, f.transfer_in, f.transfer_out, close.toString(), m.volume, m.price, short]);
  }
  for (const house of houses) for (const asset of assets) {
    const f = await flow(tx, day, asset.id, house.economic_id);
    const closing = await tx.query<{ balance: string }>(`SELECT COALESCE(balance_units,0)::TEXT balance FROM economic_accounts WHERE owner_economic_id=$1 AND asset_id=$2 AND account_type='INVENTORY' AND status='ACTIVE'`, [house.economic_id, asset.id]);
    const close = BigInt(closing.rows[0]?.balance ?? '0');
    const net = BigInt(f.net);
    const short = await shortage(tx, day, house.economic_id, asset.code);
    await tx.query(`INSERT INTO house_resource_daily_flow (house_economic_id,game_day,asset_id,opening_balance_units,production_units,consumption_units,transfer_in_units,transfer_out_units,closing_balance_units,net_flow_units,shortage_units,is_limiting_resource) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) ON CONFLICT (house_economic_id,game_day,asset_id) DO UPDATE SET opening_balance_units=EXCLUDED.opening_balance_units,production_units=EXCLUDED.production_units,consumption_units=EXCLUDED.consumption_units,transfer_in_units=EXCLUDED.transfer_in_units,transfer_out_units=EXCLUDED.transfer_out_units,closing_balance_units=EXCLUDED.closing_balance_units,net_flow_units=EXCLUDED.net_flow_units,shortage_units=EXCLUDED.shortage_units,is_limiting_resource=EXCLUDED.is_limiting_resource`, [house.economic_id, day, asset.id, (close-net).toString(), f.production, f.consumption, f.transfer_in, f.transfer_out, close.toString(), f.net, short, BigInt(short)>0]);
  }
}

export async function getHouseResourceAnalytics(repository: PostgresRepository, humanId: string, days = 14) {
  const result = await repository.query(`SELECT r.game_day, a.code resource, r.closing_balance_units balance, r.production_units production, r.consumption_units consumption, r.net_flow_units net_flow, r.shortage_units, r.is_limiting_resource, g.average_price_units price FROM house_resource_daily_flow r JOIN economic_assets a ON a.id=r.asset_id LEFT JOIN global_resource_daily_state g ON g.game_day=r.game_day AND g.asset_id=r.asset_id WHERE r.house_economic_id=(SELECT o.economic_id FROM owner_registry o JOIN humans h ON h.house_id=o.id WHERE h.id=$1) ORDER BY r.game_day DESC, a.id LIMIT $2`, [humanId, Math.max(1, days) * 5]);
  return result.rows;
}

export async function getGlobalResourceAnalytics(repository: PostgresRepository, days = 14) {
  const result = await repository.query(`SELECT r.game_day, a.code resource, r.opening_balance_units, r.production_units production, r.consumption_units consumption, (r.production_units-r.consumption_units+r.transfer_in_units-r.transfer_out_units) net_flow, r.closing_balance_units balance, r.market_volume_units volume, r.average_price_units price, r.shortage_units FROM global_resource_daily_state r JOIN economic_assets a ON a.id=r.asset_id ORDER BY r.game_day DESC, a.id LIMIT $1`, [Math.max(1, days) * 5]);
  return result.rows;
}
