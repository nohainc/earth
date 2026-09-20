import type { PostgresRepository } from './repository.ts';
import { priceUnitsToDisplayPrice, unitsToDisplayQuantity } from './market-units.ts';
import type { MarketOrder } from './types/market.dto.ts';

type ReadOrderOptions = {
  ownerRegistryId?: string;
  ownerEconomicId?: string;
  orderId?: string;
  sourceType?: string;
  statuses?: string[];
  beforeCreatedAt?: string;
  beforeId?: string;
  product?: string | null;
  limit?: number;
};

/** One canonical order query used by world, personal orders, and automation. */
export async function readMarketOrderRows(repository: PostgresRepository, options: ReadOrderOptions = {}) {
  const predicates = ['1 = 1'];
  const params: unknown[] = [];
  if (options.ownerRegistryId) {
    params.push(options.ownerRegistryId);
    predicates.push(`owner.id = $${params.length}`);
  }
  if (options.ownerEconomicId) {
    params.push(options.ownerEconomicId);
    predicates.push(`o.owner_economic_id = $${params.length}`);
  }
  if (options.orderId) {
    params.push(options.orderId);
    predicates.push(`o.id = $${params.length}`);
  }
  if (options.sourceType) {
    params.push(options.sourceType);
    predicates.push(`o.source_type = $${params.length}`);
  }
  if (options.statuses?.length) {
    params.push(options.statuses.map((status) => status.toUpperCase()));
    predicates.push(`o.status = ANY($${params.length}::TEXT[])`);
  }
  if (options.beforeCreatedAt && options.beforeId) {
    params.push(options.beforeCreatedAt, options.beforeId);
    predicates.push(`(o.created_at, o.id) < ($${params.length - 1}::TIMESTAMPTZ, $${params.length}::TEXT)`);
  }
  if (options.product) {
    params.push(`SPOT-${options.product.trim().toUpperCase()}`);
    predicates.push(`i.symbol = $${params.length}`);
  }
  params.push(Math.min(Math.max(options.limit ?? 500, 1), 2000));
  const result = await repository.query<Record<string, unknown>>(
    `SELECT o.id, o.instrument_id, o.owner_economic_id, o.side, o.status,
            o.quantity_units::TEXT, o.remaining_units::TEXT,
            o.limit_price_units::TEXT, o.rules_version, o.source_type,
            o.policy_id, o.good_til_game_day, o.created_at,
            i.symbol, i.instrument_type, i.status AS instrument_status,
            i.rules_version AS instrument_rules_version,
            i.genesis_reference_price_units::TEXT AS genesis_reference_price_units,
            i.asset_id AS base_asset_id, i.quote_asset_id,
            ba.code AS base_asset_code, qa.code AS quote_asset_code,
            COALESCE(reservation.remaining_reservation_units, 0)::TEXT AS reserved_escrow_units,
            COALESCE(reservation.initial_escrow_units, 0)::TEXT AS initial_escrow_units,
            COALESCE(reservation.escrow_asset_id, CASE WHEN o.side = 'BUY' THEN i.quote_asset_id ELSE i.asset_id END) AS escrow_asset_id,
            reservation.escrow_account_id,
            COALESCE(reservation.reservation_status, 'NONE') AS reservation_status,
            COALESCE(refunds.released_escrow_units, 0)::TEXT AS released_escrow_units,
            COALESCE(refunds.cancellation_refund_units, 0)::TEXT AS cancellation_refund_units,
            COALESCE(fills.fill_count, 0)::INTEGER AS fill_count,
            COALESCE(fills.filled_quantity_units, 0)::TEXT AS filled_quantity_units,
            COALESCE(fills.gross_value_units, 0)::TEXT AS gross_value_units,
            fills.average_price_units::TEXT AS average_price_units,
            COALESCE(fills.fees_paid_units, 0)::TEXT AS fees_paid_units,
            COALESCE(fills.consumed_escrow_units, 0)::TEXT AS consumed_escrow_units
       FROM market_orders o
       JOIN market_instruments i ON i.id = o.instrument_id
       LEFT JOIN economic_assets ba ON ba.id = i.asset_id
       LEFT JOIN economic_assets qa ON qa.id = i.quote_asset_id
       LEFT JOIN owner_registry owner ON owner.economic_id = o.owner_economic_id
       LEFT JOIN LATERAL (
         SELECT SUM(r.remaining_units) AS remaining_reservation_units,
                MAX(r.reserved_units) AS initial_escrow_units,
                MAX(r.asset_id) AS escrow_asset_id,
                MAX(r.escrow_account_id) AS escrow_account_id,
                MAX(r.status) AS reservation_status
           FROM market_order_reservations r
          WHERE r.order_id = o.id
       ) reservation ON TRUE
       LEFT JOIN LATERAL (
         SELECT
           SUM(ABS(e.delta_units)) FILTER (WHERE e.delta_units < 0) AS released_escrow_units,
           SUM(ABS(e.delta_units)) FILTER (WHERE e.delta_units < 0 AND t.correlation_id LIKE 'market-order:' || o.id || ':cancel:%') AS cancellation_refund_units
         FROM economic_transactions t
         JOIN economic_entries e ON e.transaction_id = t.id
         WHERE t.source_type = 'MARKET'
           AND t.source_id = o.id
           AND t.correlation_id LIKE 'market-order:' || o.id || ':%'
           AND e.account_id = reservation.escrow_account_id
       ) refunds ON TRUE
       LEFT JOIN LATERAL (
         SELECT COUNT(*) AS fill_count,
                SUM(f.quantity_units) AS filled_quantity_units,
                SUM(f.gross_quote_units) AS gross_value_units,
                ROUND(SUM(f.gross_quote_units)::NUMERIC / NULLIF(SUM(f.quantity_units), 0)) AS average_price_units,
                SUM(CASE WHEN f.buy_order_id = o.id THEN f.buyer_fee_units ELSE f.seller_fee_units END) AS fees_paid_units,
                SUM(CASE WHEN o.side = 'BUY' THEN f.gross_quote_units + f.buyer_fee_units ELSE f.quantity_units END) AS consumed_escrow_units
           FROM market_fills f
          WHERE f.buy_order_id = o.id OR f.sell_order_id = o.id
       ) fills ON TRUE
      WHERE ${predicates.join(' AND ')}
      ORDER BY o.created_at DESC, o.id DESC
      LIMIT $${params.length}`,
    params,
  );
  return result;
}

function decimalEscrow(units: bigint, assetId: number): string {
  return assetId === 1 ? priceUnitsToDisplayPrice(units) : unitsToDisplayQuantity(units);
}

/** Serialize every order response from the same authoritative aggregate row. */
export function serializeMarketOrder(row: Record<string, unknown>): MarketOrder {
  const quantity = BigInt(String(row.quantity_units ?? '0'));
  const remaining = BigInt(String(row.remaining_units ?? '0'));
  const filled = BigInt(String(row.filled_quantity_units ?? '0'));
  const baseAssetId = Number(row.base_asset_id ?? 2);
  const escrowAssetId = Number(row.escrow_asset_id ?? baseAssetId);
  const reservedEscrowUnits = BigInt(String(row.reserved_escrow_units ?? '0'));
  const initialEscrowUnits = BigInt(String(row.initial_escrow_units ?? '0'));
  const releasedEscrowUnits = BigInt(String(row.released_escrow_units ?? '0'));
  const cancellationRefundUnits = BigInt(String(row.cancellation_refund_units ?? '0'));
  const feesPaidUnits = BigInt(String(row.fees_paid_units ?? '0'));
  const grossValueUnits = BigInt(String(row.gross_value_units ?? '0'));
  return {
    id: String(row.id ?? ''),
    instrumentId: row.instrument_id == null ? null : String(row.instrument_id),
    instrument: row.instrument_id == null ? null : {
      id: String(row.instrument_id),
      symbol: String(row.symbol ?? ''),
      instrumentType: 'SPOT',
      baseAsset: { id: String(baseAssetId), code: row.base_asset_code == null ? null : String(row.base_asset_code), decimals: null },
      quoteAsset: { id: String(row.quote_asset_id ?? ''), code: row.quote_asset_code == null ? null : String(row.quote_asset_code), decimals: null },
      lotSize: '1',
      priceTick: '0.01',
      status: String(row.instrument_status ?? 'UNKNOWN'),
      rulesVersion: String(row.instrument_rules_version ?? row.rules_version ?? ''),
      genesisReferencePrice: row.genesis_reference_price_units == null ? null : priceUnitsToDisplayPrice(String(row.genesis_reference_price_units)),
    },
    product: row.symbol ? String(row.symbol).replace(/^SPOT-/, '').toLowerCase() : null,
    side: String(row.side ?? '').toLowerCase() as 'buy' | 'sell',
    status: String(row.status ?? ''),
    quantity: unitsToDisplayQuantity(quantity),
    filledQuantity: unitsToDisplayQuantity(filled),
    remainingQuantity: unitsToDisplayQuantity(remaining),
    limitPrice: priceUnitsToDisplayPrice(String(row.limit_price_units ?? '0')),
    rulesVersion: row.rules_version == null ? null : String(row.rules_version),
    sourceType: String(row.source_type ?? 'MANUAL'),
    policyId: row.policy_id == null ? null : String(row.policy_id),
    goodTilGameDay: row.good_til_game_day == null ? null : Number(row.good_til_game_day),
    createdAt: row.created_at == null ? null : String(row.created_at),
    fillCount: Number(row.fill_count ?? 0),
    grossValueUnits: grossValueUnits.toString(),
    grossValue: priceUnitsToDisplayPrice(grossValueUnits),
    averageFillPrice: row.average_price_units == null ? null : priceUnitsToDisplayPrice(String(row.average_price_units)),
    reservationStatus: String(row.reservation_status ?? 'NONE'),
    initialEscrowUnits: initialEscrowUnits.toString(),
    initialEscrow: decimalEscrow(initialEscrowUnits, escrowAssetId),
    remainingReservationUnits: reservedEscrowUnits.toString(),
    remainingReservation: decimalEscrow(reservedEscrowUnits, escrowAssetId),
    cancellationRefundUnits: cancellationRefundUnits.toString(),
    cancellationRefund: decimalEscrow(cancellationRefundUnits, escrowAssetId),
    filledGrossValueUnits: grossValueUnits.toString(),
    filledGrossValue: priceUnitsToDisplayPrice(grossValueUnits),
    totalFeePaidUnits: feesPaidUnits.toString(),
    totalFeePaid: priceUnitsToDisplayPrice(feesPaidUnits),
    weightedAverageFillPrice: row.average_price_units == null ? null : priceUnitsToDisplayPrice(String(row.average_price_units)),
    reservedEscrowUnits: reservedEscrowUnits.toString(),
    reservedEscrow: decimalEscrow(reservedEscrowUnits, escrowAssetId),
    feesPaidUnits: feesPaidUnits.toString(),
    feesPaid: priceUnitsToDisplayPrice(feesPaidUnits),
    releasedEscrowUnits: releasedEscrowUnits.toString(),
    releasedEscrow: decimalEscrow(releasedEscrowUnits, escrowAssetId),
  } as MarketOrder;
}
