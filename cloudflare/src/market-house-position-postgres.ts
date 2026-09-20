import type { PostgresRepository } from './repository.ts';
import {
  normalizeHouseCommodityPositions,
  type HouseCommodityPositionRow,
} from './market-house-position.ts';

const RESOURCE_CODES = ['energy', 'food', 'material', 'components', 'compute'];

export async function readHouseCommodityPositions(
  repository: PostgresRepository,
  houseId: string,
) {
  const result = await repository.query<HouseCommodityPositionRow>(
    `SELECT LOWER(a.code) AS product,
            COALESCE(SUM(CASE WHEN account.account_type = 'INVENTORY'
                              THEN account.balance_units ELSE 0 END), 0)::TEXT AS current_units,
            COALESCE((
              SELECT SUM(r.remaining_units)
                FROM market_order_reservations r
                JOIN market_orders order_row ON order_row.id = r.order_id
               WHERE order_row.owner_economic_id = owner.economic_id
                 AND order_row.side = 'SELL'
                 AND order_row.status IN ('OPEN', 'PARTIAL')
                 AND r.asset_id = a.id
                 AND r.status = 'ACTIVE'
            ), 0)::TEXT AS reserved_units
       FROM economic_assets a
       CROSS JOIN owner_registry owner
       LEFT JOIN economic_accounts account
         ON account.owner_economic_id = owner.economic_id
        AND account.asset_id = a.id
        AND account.status = 'ACTIVE'
      WHERE owner.id = $1
        AND owner.owner_type = 'HOUSE'
        AND LOWER(a.code) = ANY($2::TEXT[])
      GROUP BY a.id, a.code, owner.economic_id
      ORDER BY array_position($2::TEXT[], LOWER(a.code))`,
    [houseId, RESOURCE_CODES],
  );

  const byProduct = new Map(result.rows.map((row) => [row.product, row]));
  const rows = RESOURCE_CODES.map((product) => byProduct.get(product) ?? {
    product,
    current_units: '0',
    reserved_units: '0',
  });
  const positions = normalizeHouseCommodityPositions(rows).map((position) => ({
    product: position.product,
    currentQuantity: position.currentQuantity,
    reservedQuantity: position.reservedQuantity,
    availableQuantity: position.availableQuantity,
  }));
  return {
    positions,
    generatedFrom: 'postgres-canonical-house-market-position',
  };
}
