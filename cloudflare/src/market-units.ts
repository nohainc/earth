const QUANTITY_SCALE = 1_000_000n;
const PRICE_SCALE = 100n;
const RATE_SCALE = 1_000_000n;

function fixedParts(value: unknown, decimals: number): { negative: boolean; whole: bigint; fraction: string } {
  const text = typeof value === 'number' ? (Number.isFinite(value) ? String(value) : '') : String(value ?? '').trim();
  const match = text.match(/^(−|-)?(\d+)(?:\.(\d+))?$/);
  if (!match || (match[3]?.length ?? 0) > decimals) throw new Error(`Invalid decimal value; expected at most ${decimals} fractional digits`);
  return { negative: match[1] === '-' || match[1] === '−', whole: BigInt(match[2]), fraction: match[3] ?? '' };
}

function toUnits(value: unknown, scale: bigint, decimals: number): bigint {
  const parts = fixedParts(value, decimals);
  const units = parts.whole * scale + BigInt(parts.fraction.padEnd(decimals, '0'));
  return parts.negative ? -units : units;
}

function fromUnits(units: bigint, scale: bigint, decimals: number): string {
  const negative = units < 0n;
  const absolute = negative ? -units : units;
  const whole = absolute / scale;
  const fraction = String(absolute % scale).padStart(decimals, '0');
  return `${negative ? '-' : ''}${whole}.${fraction}`;
}

export function displayQuantityToUnits(value: unknown): bigint {
  const units = toUnits(value, QUANTITY_SCALE, 6);
  if (units <= 0n) throw new Error('Market quantity must be positive');
  return units;
}

export function unitsToDisplayQuantity(units: bigint | string | number): string {
  return fromUnits(BigInt(units), QUANTITY_SCALE, 6);
}

export function displayPriceToUnits(value: unknown): bigint {
  const units = toUnits(value, PRICE_SCALE, 2);
  if (units <= 0n) throw new Error('Market price must be positive');
  return units;
}

export function priceUnitsToDisplayPrice(units: bigint | string | number): string {
  return fromUnits(BigInt(units), PRICE_SCALE, 2);
}

function roundedDivide(numerator: bigint, denominator: bigint): bigint {
  return (numerator + denominator / 2n) / denominator;
}

export function calculateQuoteUnits(quantityUnits: bigint, priceUnits: bigint): bigint {
  if (quantityUnits < 0n || priceUnits < 0n) throw new Error('Market units cannot be negative');
  return roundedDivide(quantityUnits * priceUnits, QUANTITY_SCALE);
}

export function calculateFeeUnits(quoteUnits: bigint, rate: unknown): bigint {
  if (quoteUnits < 0n) throw new Error('Quote units cannot be negative');
  const rateUnits = toUnits(rate, RATE_SCALE, 6);
  if (rateUnits < 0n || rateUnits > 50_000n) throw new Error('Market fee rate is outside engine bounds');
  return roundedDivide(quoteUnits * rateUnits, RATE_SCALE);
}

export function displayRateToBps(rate: unknown): number {
  const rateUnits = toUnits(rate, RATE_SCALE, 6);
  if (rateUnits < 0n || rateUnits > 50_000n || rateUnits % 100n !== 0n) throw new Error('Market fee rate must be representable in basis points');
  return Number(rateUnits / 100n);
}

export function calculateFeeUnitsBps(quoteUnits: bigint, feeBps: number | string | bigint): bigint {
  const bps = BigInt(feeBps);
  if (quoteUnits < 0n || bps < 0n || bps > 500n) throw new Error('Market fee basis points are outside engine bounds');
  return roundedDivide(quoteUnits * bps, 10_000n);
}
