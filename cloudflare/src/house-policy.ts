export type HousePolicy = {
  id: string;
  houseId: string;
  policyType: 'OPERATING' | 'INVENTORY_RESERVE' | 'MARKET_STANDING';
  version: number;
  effectiveFromGameDay: number;
  status: 'ACTIVE' | 'PAUSED' | 'SUPERSEDED';
  /** @deprecated Preserved for historical rows; House automation execution does not use presets. */
  operatingMode: 'CONSERVATIVE' | 'BALANCED' | 'GROWTH' | 'CUSTOM';
  dailySpendCapUnits: bigint;
  minimumReserveUnits: Record<string, bigint>;
  sellAboveUnits: Record<string, bigint>;
  maxInputPriceUnits: Record<string, bigint>;
  minSalePriceUnits: Record<string, bigint>;
  maxBuyQuantityUnits: Record<string, bigint>;
  maxSellQuantityUnits: Record<string, bigint>;
  rulesVersion: string;
};

export type PolicyReasonCode =
  | 'MINIMUM_RESERVE_SHORTFALL'
  | 'SELL_ABOVE_THRESHOLD'
  | 'MISSING_BUY_PRICE'
  | 'MISSING_SELL_PRICE'
  | 'SPEND_CAP_EXHAUSTED'
  | 'OPEN_ORDER_EXISTS';

export type PolicyEvaluation = {
  action: 'BUY' | 'SELL' | 'NONE';
  product: string;
  quantityUnits: bigint;
  priceLimitUnits: bigint | null;
  reasonCode: PolicyReasonCode;
  reason: string;
};

function nonNegativeMap(input: Record<string, bigint | string | number> = {}): Record<string, bigint> {
  return Object.fromEntries(Object.entries(input).map(([key, value]) => {
    const parsed = typeof value === 'bigint' ? value : BigInt(String(value));
    if (parsed < 0n) throw new Error(`Policy value for ${key} must be non-negative`);
    return [key.toUpperCase(), parsed];
  }));
}

const CANONICAL_RESOURCES = new Set(['FOOD', 'ENERGY', 'MATERIAL', 'COMPONENTS', 'COMPUTE']);
const BIGINT_MAX = 9_223_372_036_854_775_807n;

function validateMap(name: string, input: Record<string, bigint>, options: { positive?: boolean } = {}): void {
  for (const [rawAsset, value] of Object.entries(input)) {
    const asset = rawAsset.toUpperCase();
    if (!CANONICAL_RESOURCES.has(asset)) throw new Error(`${name} contains unknown resource code ${rawAsset}`);
    if (value < 0n || value > BIGINT_MAX || (options.positive && value <= 0n)) {
      throw new Error(`${name} value for ${asset} is outside the supported integer bounds`);
    }
  }
}

export function validateHousePolicy(policy: HousePolicy): void {
  const maps = [
    ['minimumReserveUnits', policy.minimumReserveUnits, {}],
    ['sellAboveUnits', policy.sellAboveUnits, {}],
    ['maxBuyQuantityUnits', policy.maxBuyQuantityUnits, {}],
    ['maxSellQuantityUnits', policy.maxSellQuantityUnits, {}],
    ['maxInputPriceUnits', policy.maxInputPriceUnits, { positive: true }],
    ['minSalePriceUnits', policy.minSalePriceUnits, { positive: true }],
  ] as const;
  for (const [name, values, options] of maps) validateMap(name, values, options);
  for (const [asset, threshold] of Object.entries(policy.sellAboveUnits)) {
    const minimum = policy.minimumReserveUnits[asset] ?? 0n;
    if (threshold < minimum) throw new Error(`sellAbove for ${asset} cannot be below minimumReserve`);
  }
}

export function evaluateInventoryPolicy(policy: HousePolicy, inventory: Record<string, bigint | string | number>, dailySpendUsedUnits: bigint): PolicyEvaluation[] {
  if (policy.status !== 'ACTIVE') return [];
  validateHousePolicy(policy);
  if (dailySpendUsedUnits < 0n || dailySpendUsedUnits > policy.dailySpendCapUnits) throw new Error('Policy spend usage is outside the configured cap');
  const current = nonNegativeMap(inventory);
  const evaluations: PolicyEvaluation[] = [];
  for (const [asset, minimumReserve] of Object.entries(policy.minimumReserveUnits)) {
    const held = current[asset] ?? 0n;
    const shortfall = minimumReserve - held;
    if (shortfall <= 0n) continue;
    const configuredMaximum = policy.maxBuyQuantityUnits[asset];
    const quantity = configuredMaximum === undefined
      ? shortfall
      : (shortfall < configuredMaximum ? shortfall : configuredMaximum);
    if (quantity <= 0n) continue;
    const priceLimit = policy.maxInputPriceUnits[asset] ?? null;
    evaluations.push({ action: 'BUY', product: asset, quantityUnits: quantity, priceLimitUnits: priceLimit, reasonCode: 'MINIMUM_RESERVE_SHORTFALL', reason: `${asset} is below the saved minimum reserve` });
  }
  return evaluations;
}

export function evaluateSalePolicy(policy: HousePolicy, inventory: Record<string, bigint | string | number>): PolicyEvaluation[] {
  if (policy.status !== 'ACTIVE') return [];
  validateHousePolicy(policy);
  const current = nonNegativeMap(inventory);
  return Object.entries(policy.sellAboveUnits).flatMap(([asset, threshold]) => {
    const excess = (current[asset] ?? 0n) - threshold;
    if (excess <= 0n) return [];
    const configuredMaximum = policy.maxSellQuantityUnits[asset];
    const quantity = configuredMaximum === undefined
      ? excess
      : (excess < configuredMaximum ? excess : configuredMaximum);
    if (quantity <= 0n) return [];
    const priceLimit = policy.minSalePriceUnits[asset] ?? null;
    return [{ action: 'SELL' as const, product: asset, quantityUnits: quantity, priceLimitUnits: priceLimit, reasonCode: 'SELL_ABOVE_THRESHOLD', reason: `${asset} is above the saved sell-above threshold` }];
  });
}
