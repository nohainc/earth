/** Stable health bands used by simulation CI and reports. */
export const BALANCE_TARGETS = Object.freeze({
  survivalFloor: 0.90,
  shortageFrequencyCeiling: 0.25,
  wealthConcentrationCeiling: 8,
  utilizationFloor: 0.15,
  creditExposureToSupplyCeiling: 0.75,
});

export function evaluateBalanceHealth(result, targets = BALANCE_TARGETS) {
  const survival = result.houses > 0 ? result.survivingHouses / result.houses : 0;
  const utilizationValues = Object.values(result.averageUtilization ?? {}).map(Number);
  const meanUtilization = utilizationValues.length ? utilizationValues.reduce((sum, value) => sum + value, 0) / utilizationValues.length : 0;
  const checks = {
    survival: survival >= targets.survivalFloor,
    shortages: Number(result.shortageFrequency ?? 0) <= targets.shortageFrequencyCeiling,
    concentration: Number(result.wealth?.maxToMean ?? Number.POSITIVE_INFINITY) <= targets.wealthConcentrationCeiling,
    utilization: meanUtilization >= targets.utilizationFloor,
    creditExposure: Number(result.creditExposureRatio ?? 0) <= targets.creditExposureToSupplyCeiling,
  };
  return { status: Object.values(checks).every(Boolean) ? 'HEALTHY' : 'REVIEW', checks, survivalRate: survival, meanUtilization, targets };
}
