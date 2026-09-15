export const WORLD_CONDITIONS_RULES_VERSION = 'world-conditions-v1';
export const WORLD_CONDITION_EFFECTS = [
  'SUPPLY_MULTIPLIER', 'DEMAND_MULTIPLIER', 'CAPACITY_MULTIPLIER', 'LABOR_INDEX', 'CONSTRUCTION_INDEX',
] as const;

export type WorldConditionEffect = typeof WORLD_CONDITION_EFFECTS[number];

export function conditionIsEffective(condition: { effectiveFromGameDay: number; effectiveToGameDay: number | null }, gameDay: number) {
  return gameDay >= condition.effectiveFromGameDay && (condition.effectiveToGameDay == null || gameDay <= condition.effectiveToGameDay);
}

export function applyConditionModifier(base: number, modifierBps: number) {
  if (!Number.isFinite(base) || !Number.isFinite(modifierBps)) throw new Error('World condition modifier must be finite');
  return Math.max(0, base * (1 + modifierBps / 10_000));
}

/** Fixed-point variant used by settlement; it never passes authoritative units through Number. */
export function applyConditionModifierUnits(base: bigint, modifierBps: number): bigint {
  if (base < 0n || !Number.isInteger(modifierBps) || modifierBps < -5000 || modifierBps > 5000) throw new Error('World condition unit modifier is invalid');
  return base * BigInt(10_000 + modifierBps) / 10_000n;
}

export function applyConditionStack(base: bigint, modifiers: readonly number[]): bigint {
  return modifiers.reduce((value, modifier) => applyConditionModifierUnits(value, modifier), base);
}
