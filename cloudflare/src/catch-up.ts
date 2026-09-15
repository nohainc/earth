export const ENTRY_SUPPORT_RULES = {
  version: 'entry-support-v1',
  maxAgeDays: 30,
  maxBuildings: 0,
  maxMarketOrders: 0,
  resourceBundleDisplayUnits: { FOOD: 10, MATERIAL: 20, ENERGY: 10 },
  creditUnits: 0,
} as const;

export function evaluateEntrySupportEligibility(input: {
  onboardingStatus: string;
  currentGameDay: number;
  entryGameDay: number | null;
  eligibleUntilGameDay: number | null;
  buildingCount: number;
  marketOrderCount: number;
  affiliationCount: number;
  supportStatus: string;
}) {
  const age = input.entryGameDay == null ? null : input.currentGameDay - input.entryGameDay;
  const withinWindow = input.eligibleUntilGameDay != null && input.currentGameDay <= input.eligibleUntilGameDay;
  const eligible = input.supportStatus === 'ELIGIBLE' && input.onboardingStatus === 'ACTIVE' &&
    age != null && age >= 0 && age <= ENTRY_SUPPORT_RULES.maxAgeDays && withinWindow &&
    input.buildingCount <= ENTRY_SUPPORT_RULES.maxBuildings &&
    input.marketOrderCount <= ENTRY_SUPPORT_RULES.maxMarketOrders &&
    input.affiliationCount === 0;
  return { eligible, ageDays: age, reason: eligible ? 'ELIGIBLE' : 'HOUSE_HAS_PROGRESS_OR_SUPPORT_WAS_CLAIMED' };
}
