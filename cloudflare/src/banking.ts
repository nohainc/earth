export type LoanQuoteInput = {
  requestedUnits: bigint;
  termDays: number;
  collateralUnits: bigint;
  guaranteedUnits: bigint;
  borrowerCashflowUnits: bigint;
  availableReserveUnits: bigint;
  baseRateBps: bigint;
  maxLoanToCollateralBps: bigint;
  maxLoanToCashflowBps: bigint;
  minimumReserveRatioBps: bigint;
};

export function quoteLoan(input: LoanQuoteInput): { eligible: boolean; approvedUnits: bigint; rateBps: bigint; reason: string } {
  if ([input.requestedUnits, input.collateralUnits, input.guaranteedUnits, input.borrowerCashflowUnits, input.availableReserveUnits, input.baseRateBps, input.maxLoanToCollateralBps, input.maxLoanToCashflowBps, input.minimumReserveRatioBps].some((value) => value < 0n)) throw new Error('Loan quote quantities cannot be negative');
  if (!Number.isInteger(input.termDays) || input.termDays <= 0) throw new Error('Loan term must be a positive integer');
  if (input.requestedUnits <= 0n) return { eligible: false, approvedUnits: 0n, rateBps: input.baseRateBps, reason: 'requested amount must be positive' };
  const reserveCapacity = (input.availableReserveUnits * (10000n - input.minimumReserveRatioBps)) / 10000n;
  const collateralCapacity = ((input.collateralUnits + input.guaranteedUnits) * input.maxLoanToCollateralBps) / 10000n;
  const cashflowCapacity = (input.borrowerCashflowUnits * input.maxLoanToCashflowBps) / 10000n;
  const approvedUnits = [input.requestedUnits, reserveCapacity, collateralCapacity, cashflowCapacity].reduce((min, value) => value < min ? value : min);
  if (approvedUnits <= 0n) return { eligible: false, approvedUnits: 0n, rateBps: input.baseRateBps, reason: 'insufficient reserve, collateral, guarantee, or observable cash flow' };
  return { eligible: true, approvedUnits, rateBps: input.baseRateBps, reason: 'eligible' };
}
