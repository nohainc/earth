/**
 * V5 marginal progressive pricing.
 *
 * This module is deliberately free of HTTP, database, clock, and floating-point
 * concerns. Callers select the applicable rule version before invoking it.
 */

import { roundDivide } from './units.ts';

export type ProgressiveBracket = {
  ordinal: number;
  lowerBound: bigint;
  upperBound: bigint | null;
  multiplierNumerator: bigint;
  multiplierDenominator: bigint;
};

export type ProgressiveChargeInput = {
  quantity: bigint;
  baseRate: bigint;
  brackets: readonly ProgressiveBracket[];
};

export type ProgressiveAllocation = {
  ordinal: number;
  quantity: bigint;
  lowerBound: bigint;
  upperBound: bigint | null;
  multiplierNumerator: bigint;
  multiplierDenominator: bigint;
  charge: bigint;
};

export type ProgressiveCharge = {
  totalCharge: bigint;
  quantity: bigint;
  baseRate: bigint;
  currentBracket: number | null;
  allocations: ProgressiveAllocation[];
};

function assertNonNegative(value: bigint, name: string): void {
  if (value < 0n) throw new Error(`${name} must be non-negative`);
}

/** Validate the structural and monotonic invariants of a schedule. */
export function validateProgressiveBrackets(brackets: readonly ProgressiveBracket[]): void {
  if (brackets.length === 0) throw new Error('Progressive schedule must contain at least one bracket');
  if (brackets[0].lowerBound !== 0n) throw new Error('Progressive schedule must begin at zero');

  let previousMultiplier: ProgressiveBracket | null = null;
  for (let index = 0; index < brackets.length; index += 1) {
    const bracket = brackets[index];
    if (bracket.ordinal !== index + 1) throw new Error('Progressive bracket ordinals must be contiguous');
    assertNonNegative(bracket.lowerBound, 'Bracket lower bound');
    if (bracket.upperBound !== null && bracket.upperBound <= bracket.lowerBound) throw new Error('Bracket upper bound must be greater than its lower bound');
    if (index > 0 && brackets[index - 1].upperBound !== bracket.lowerBound) throw new Error('Progressive brackets must be contiguous');
    if (index < brackets.length - 1 && bracket.upperBound === null) throw new Error('Only the final progressive bracket may be open-ended');
    if (bracket.multiplierNumerator < 0n || bracket.multiplierDenominator <= 0n) throw new Error('Progressive multiplier must be non-negative with a positive denominator');
    if (previousMultiplier && bracket.multiplierNumerator * previousMultiplier.multiplierDenominator < previousMultiplier.multiplierNumerator * bracket.multiplierDenominator) {
      throw new Error('Progressive marginal multipliers must be non-decreasing');
    }
    previousMultiplier = bracket;
  }
  if (brackets.at(-1)?.upperBound !== null) throw new Error('Progressive schedule must end with an open-ended bracket');
}

/**
 * Calculate only marginal quantities in each bracket. Rounding is applied per
 * bracket, making the result stable, explainable, and safe for integer CREDIT.
 */
export function calculateProgressiveCharge(input: ProgressiveChargeInput): ProgressiveCharge {
  assertNonNegative(input.quantity, 'Quantity');
  assertNonNegative(input.baseRate, 'Base rate');
  validateProgressiveBrackets(input.brackets);

  let totalCharge = 0n;
  const allocations: ProgressiveAllocation[] = [];
  for (const bracket of input.brackets) {
    if (input.quantity <= bracket.lowerBound) break;
    const end = bracket.upperBound === null || input.quantity < bracket.upperBound ? input.quantity : bracket.upperBound;
    const quantity = end - bracket.lowerBound;
    if (quantity <= 0n) continue;
    const charge = roundDivide(quantity * input.baseRate * bracket.multiplierNumerator, bracket.multiplierDenominator);
    allocations.push({ ...bracket, quantity, charge });
    totalCharge += charge;
  }
  return {
    totalCharge,
    quantity: input.quantity,
    baseRate: input.baseRate,
    currentBracket: allocations.at(-1)?.ordinal ?? null,
    allocations,
  };
}

export function progressiveChargeToJSON(result: ProgressiveCharge): Record<string, unknown> {
  return {
    totalCharge: result.totalCharge.toString(),
    quantity: result.quantity.toString(),
    baseRate: result.baseRate.toString(),
    currentBracket: result.currentBracket,
    allocations: result.allocations.map((allocation) => Object.fromEntries(
      Object.entries(allocation).map(([key, value]) => [key, typeof value === 'bigint' ? value.toString() : value]),
    )),
  };
}
