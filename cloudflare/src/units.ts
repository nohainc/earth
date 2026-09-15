/**
 * Fixed-point primitives for authoritative economic quantities.
 *
 * These helpers intentionally return bigint. Conversion to Number is reserved
 * for presentation-only code and must never be used to decide a ledger effect.
 */
export function parseFixedUnits(value: unknown, scale: bigint, maxFractionDigits: number): bigint {
  const text = typeof value === 'number' ? (Number.isFinite(value) ? String(value) : '') : String(value ?? '').trim();
  const match = text.match(/^(-?)(\d+)(?:\.(\d+))?$/);
  if (!match || (match[3]?.length ?? 0) > maxFractionDigits) throw new Error('Invalid fixed-point value');
  const fraction = (match[3] ?? '').padEnd(maxFractionDigits, '0');
  const units = BigInt(match[2]) * scale + BigInt(fraction || '0');
  return match[1] === '-' ? -units : units;
}

export function roundDivide(numerator: bigint, denominator: bigint): bigint {
  if (denominator <= 0n) throw new Error('Division denominator must be positive');
  if (numerator < 0n) return -roundDivide(-numerator, denominator);
  return (numerator + denominator / 2n) / denominator;
}

export function formatFixedUnits(units: bigint, scale: bigint, decimals: number): string {
  if (scale <= 0n || decimals < 0) throw new Error('Invalid fixed-point format');
  const negative = units < 0n;
  const absolute = negative ? -units : units;
  const whole = absolute / scale;
  const fraction = String(absolute % scale).padStart(decimals, '0');
  return `${negative ? '-' : ''}${whole}.${fraction}`;
}

export function nonNegativeBigInt(value: unknown, label = 'units'): bigint {
  const units = typeof value === 'bigint' ? value : BigInt(String(value ?? '').trim());
  if (units < 0n) throw new Error(`${label} must be non-negative`);
  return units;
}
