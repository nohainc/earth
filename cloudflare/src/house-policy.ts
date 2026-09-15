export type HousePolicy = {
  id: string;
  houseId: string;
  policyType: 'OPERATING' | 'INVENTORY_RESERVE' | 'MARKET_STANDING';
  version: number;
  effectiveFromGameDay: number;
  status: 'ACTIVE' | 'PAUSED' | 'SUPERSEDED';
  operatingMode: 'CONSERVATIVE' | 'BALANCED' | 'GROWTH' | 'CUSTOM';
  dailySpendCapUnits: bigint;
  reserveFloorUnits: Record<string, bigint>;
  maxInputPriceUnits: Record<string, bigint>;
  minSalePriceUnits: Record<string, bigint>;
  procurementQuantityUnits: Record<string, bigint>;
  rulesVersion: string;
};

export type PolicyEvaluation = { action: 'BUY' | 'SELL' | 'NONE'; product: string; quantityUnits: bigint; priceLimitUnits: bigint | null; reason: string };

function nonNegativeMap(input: Record<string, bigint | string | number> = {}): Record<string, bigint> {
  return Object.fromEntries(Object.entries(input).map(([key, value]) => {
    const parsed = typeof value === 'bigint' ? value : BigInt(String(value));
    if (parsed < 0n) throw new Error(`Policy value for ${key} must be non-negative`);
    return [key.toUpperCase(), parsed];
  }));
}

export function evaluateInventoryPolicy(policy: HousePolicy, inventory: Record<string, bigint | string | number>, dailySpendUsedUnits: bigint): PolicyEvaluation[] {
  if (policy.status !== 'ACTIVE') return [];
  if (dailySpendUsedUnits < 0n || dailySpendUsedUnits > policy.dailySpendCapUnits) throw new Error('Policy spend usage is outside the configured cap');
  const current = nonNegativeMap(inventory);
  const evaluations: PolicyEvaluation[] = [];
  for (const [asset, floor] of Object.entries(policy.reserveFloorUnits)) {
    const held = current[asset] ?? 0n;
    if (held >= floor) continue;
    const quantity = policy.procurementQuantityUnits[asset] ?? floor - held;
    const priceLimit = policy.maxInputPriceUnits[asset] ?? null;
    evaluations.push({ action: 'BUY', product: asset, quantityUnits: quantity, priceLimitUnits: priceLimit, reason: `${asset} is below the saved House reserve floor` });
  }
  return evaluations;
}

export function evaluateSalePolicy(policy: HousePolicy, inventory: Record<string, bigint | string | number>): PolicyEvaluation[] {
  if (policy.status !== 'ACTIVE') return [];
  const current = nonNegativeMap(inventory);
  return Object.entries(policy.minSalePriceUnits).flatMap(([asset, priceLimit]) => {
    const floor = policy.reserveFloorUnits[asset] ?? 0n;
    const excess = (current[asset] ?? 0n) - floor;
    if (excess <= 0n) return [];
    return [{ action: 'SELL' as const, product: asset, quantityUnits: excess, priceLimitUnits: priceLimit, reason: `${asset} is above the saved House reserve floor` }];
  });
}
