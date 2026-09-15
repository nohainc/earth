export type BuildingTierBase = {
  familyCode: string;
  tier: 1;
  constructionCreditUnits: bigint;
  constructionMinutes: bigint;
  operatingCreditUnits: bigint;
  slotFootprint: bigint;
  inputUnits: Record<string, bigint>;
  outputUnits: Record<string, bigint>;
  serviceCapacityUnits: bigint;
};

export type DerivedBuildingTier = Omit<BuildingTierBase, 'tier'> & {
  tier: 1 | 2 | 3 | 4 | 5;
  formulaVersion: 'building-formula-v1';
};

// Deliberately explicit and integer-only. Coefficients are tunable balance
// data, not hidden client-side behavior.
export const BUILDING_TIER_MULTIPLIERS_BPS = [10_000n, 14_000n, 19_600n, 27_440n, 38_416n] as const;

function scaled(value: bigint, multiplierBps: bigint): bigint {
  return value * multiplierBps / 10_000n;
}

function scaledMap(values: Record<string, bigint>, multiplierBps: bigint): Record<string, bigint> {
  return Object.fromEntries(Object.entries(values).map(([key, value]) => [key.toUpperCase(), scaled(value, multiplierBps)]));
}

export function deriveBuildingTier(base: BuildingTierBase, tier: 1 | 2 | 3 | 4 | 5): DerivedBuildingTier {
  if (base.tier !== 1) throw new Error('Formula input must be a Tier 1 family definition');
  if (![1, 2, 3, 4, 5].includes(tier as number)) throw new Error('Building tier must be between 1 and 5');
  const multiplier = BUILDING_TIER_MULTIPLIERS_BPS[tier - 1];
  return {
    familyCode: base.familyCode,
    tier,
    constructionCreditUnits: scaled(base.constructionCreditUnits, multiplier),
    constructionMinutes: scaled(base.constructionMinutes, multiplier),
    operatingCreditUnits: scaled(base.operatingCreditUnits, multiplier),
    slotFootprint: base.slotFootprint,
    inputUnits: scaledMap(base.inputUnits, multiplier),
    outputUnits: scaledMap(base.outputUnits, multiplier),
    serviceCapacityUnits: scaled(base.serviceCapacityUnits, multiplier),
    formulaVersion: 'building-formula-v1',
  };
}

export function deriveAllBuildingTiers(base: BuildingTierBase): DerivedBuildingTier[] {
  return ([1, 2, 3, 4, 5] as const).map((tier) => deriveBuildingTier(base, tier));
}
