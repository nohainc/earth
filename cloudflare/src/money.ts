import { formatFixedUnits, parseFixedUnits, roundDivide } from './units.ts';

const MONEY_PATTERN = /^(-?)(\d+)(?:\.(\d{1,2}))?$/;
const RATE_PATTERN = /^(-?)(\d+)(?:\.(\d{1,6}))?$/;
const RATE_SCALE = 1_000_000n;

/** Smallest authoritative CREDIT denomination. Never convert this to Number. */
export type CreditUnits = bigint;

export function moneyToCents(value: unknown): bigint {
  if (typeof value === 'string' && !MONEY_PATTERN.test(value.trim())) throw new Error('Invalid decimal value');
  return parseFixedUnits(value, 100n, 2);
}

/** Parses a user/API CREDIT amount exactly into ledger units. */
export function parseCreditAmount(value: unknown): CreditUnits {
  return moneyToCents(value);
}

/** Formats exact ledger CREDIT units for display without floating-point conversion. */
export function formatCreditUnits(units: CreditUnits): string {
  return centsToMoney(units);
}

export function quantityToCents(value: unknown): bigint {
  return roundDivide(parseFixedUnits(value, RATE_SCALE, 6), 10_000n);
}

export function centsToMoney(cents: bigint): string {
  return formatFixedUnits(cents, 100n, 2);
}

export function rateToMicros(value: unknown): bigint {
  if (typeof value === 'string' && !RATE_PATTERN.test(value.trim())) throw new Error('Invalid decimal value');
  return parseFixedUnits(value, RATE_SCALE, 6);
}

export function taxToCents(taxableAmount: unknown, rate: unknown): bigint {
  const cents = moneyToCents(taxableAmount);
  const micros = rateToMicros(rate);
  if (cents < 0n || micros < 0n || micros > 250_000n) throw new Error('Tax inputs are outside engine bounds');
  return roundDivide(cents * micros, RATE_SCALE);
}

export function marketValueToCents(quantity: bigint | number | string, unitPrice: unknown): bigint {
  const quantityUnits = typeof quantity === 'number'
    ? (Number.isSafeInteger(quantity) ? BigInt(quantity) : 0n)
    : BigInt(String(quantity));
  if (quantityUnits <= 0n) throw new Error('Market quantity must be a positive integer');
  const cents = moneyToCents(unitPrice);
  if (cents <= 0n) throw new Error('Market price must be positive');
  return quantityUnits * cents;
}

export function rateAmountToCents(amountCents: bigint, rate: unknown, maximumRate: unknown = '0.05'): bigint {
  const micros = rateToMicros(rate);
  const maximumMicros = rateToMicros(maximumRate);
  if (amountCents < 0n || micros < 0n || micros > maximumMicros) throw new Error('Rate inputs are outside engine bounds');
  return roundDivide(amountCents * micros, RATE_SCALE);
}

export function compoundRateAmountToCents(amountCents: bigint, ...rates: unknown[]): bigint {
  if (amountCents < 0n) throw new Error('Rate base must not be negative');
  let numerator = amountCents;
  let denominator = 1n;
  for (const rate of rates) {
    const micros = rateToMicros(rate);
    if (micros < 0n || micros > 3_000_000n) throw new Error('Compound rate is outside engine bounds');
    numerator *= micros;
    denominator *= RATE_SCALE;
  }
  return roundDivide(numerator, denominator);
}
