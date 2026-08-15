const MONEY_PATTERN = /^(-?)(\d+)(?:\.(\d{1,2}))?$/;
const RATE_PATTERN = /^(-?)(\d+)(?:\.(\d{1,6}))?$/;
const RATE_SCALE = 1_000_000n;

function decimalParts(value: unknown, pattern: RegExp): { negative: boolean; whole: bigint; fraction: string } {
  const text = typeof value === 'number' ? (Number.isFinite(value) ? String(value) : '') : String(value ?? '').trim();
  const match = text.match(pattern);
  if (!match) throw new Error('Invalid decimal value');
  return { negative: match[1] === '-', whole: BigInt(match[2]), fraction: match[3] ?? '' };
}

export function moneyToCents(value: unknown): bigint {
  const parts = decimalParts(value, MONEY_PATTERN);
  const cents = parts.whole * 100n + BigInt((parts.fraction + '00').slice(0, 2));
  return parts.negative ? -cents : cents;
}

export function centsToMoney(cents: bigint): string {
  const negative = cents < 0n;
  const absolute = negative ? -cents : cents;
  const whole = absolute / 100n;
  const fraction = String(absolute % 100n).padStart(2, '0');
  return `${negative ? '-' : ''}${whole}.${fraction}`;
}

export function rateToMicros(value: unknown): bigint {
  const parts = decimalParts(value, RATE_PATTERN);
  const micros = parts.whole * RATE_SCALE + BigInt((parts.fraction.padEnd(6, '0')).slice(0, 6));
  return parts.negative ? -micros : micros;
}

export function taxToCents(taxableAmount: unknown, rate: unknown): bigint {
  const cents = moneyToCents(taxableAmount);
  const micros = rateToMicros(rate);
  if (cents < 0n || micros < 0n || micros > 250_000n) throw new Error('Tax inputs are outside engine bounds');
  return (cents * micros + RATE_SCALE / 2n) / RATE_SCALE;
}
