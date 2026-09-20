import { unitsToDisplayQuantity } from './market-units.ts';
import type { HouseCommodityPosition } from './types/market.dto.ts';

export type HouseCommodityPositionRow = {
  product: string;
  current_units: string;
  reserved_units: string;
};

/**
 * Converts the canonical atomic resource position into the player-facing
 * quantity scale. All arithmetic stays in bigint until this boundary.
 */
export function normalizeHouseCommodityPosition(
  row: HouseCommodityPositionRow,
): HouseCommodityPosition {
  const currentUnits = BigInt(String(row.current_units ?? '0'));
  const reservedUnits = BigInt(String(row.reserved_units ?? '0'));
  if (currentUnits < 0n || reservedUnits < 0n) {
    throw new Error(`Negative commodity position for ${row.product}`);
  }
  if (reservedUnits > currentUnits) {
    throw new Error(`Reserved commodity position exceeds current balance for ${row.product}`);
  }
  const availableUnits = currentUnits - reservedUnits;
  return {
    product: row.product,
    currentUnits: currentUnits.toString(),
    reservedUnits: reservedUnits.toString(),
    availableUnits: availableUnits.toString(),
    currentQuantity: unitsToDisplayQuantity(currentUnits),
    reservedQuantity: unitsToDisplayQuantity(reservedUnits),
    availableQuantity: unitsToDisplayQuantity(availableUnits),
  };
}

export function normalizeHouseCommodityPositions(
  rows: HouseCommodityPositionRow[],
): HouseCommodityPosition[] {
  return rows.map(normalizeHouseCommodityPosition);
}
