export const WORLD_CONDITIONS_RULES_VERSION = 'world-conditions-v1';
export const WORLD_CONDITION_SCOPES = ['EARTH', 'CORPORATION'] as const;
export type WorldConditionScope = typeof WORLD_CONDITION_SCOPES[number];

/**
 * The only supported condition effects are those with a named authoritative
 * consumer. All effects use the same fixed-point, sequential BPS stacking rule;
 * no client or generic world-condition code may invent a second interpretation.
 */
export const WORLD_CONDITION_EFFECT_REGISTRY = {
  SUPPLY_MULTIPLIER: {
    consumer: 'building-settlement-v2.output-resource-flow',
    stacking: 'SEQUENTIAL_BPS' as const,
    unit: 'RESOURCE_UNITS' as const,
  },
  DEMAND_MULTIPLIER: {
    consumer: 'building-settlement-v2.input-resource-flow+service-settlement.house-demand',
    stacking: 'SEQUENTIAL_BPS' as const,
    unit: 'RESOURCE_UNITS' as const,
  },
  CAPACITY_MULTIPLIER: {
    consumer: 'service-settlement.provider-capacity',
    stacking: 'SEQUENTIAL_BPS' as const,
    unit: 'RESOURCE_UNITS' as const,
  },
  LABOR_INDEX: {
    consumer: 'territory-capacity.construction-quote',
    stacking: 'SEQUENTIAL_BPS' as const,
    unit: 'GAME_MINUTES' as const,
  },
  CONSTRUCTION_INDEX: {
    consumer: 'territory-capacity.construction-quote',
    stacking: 'SEQUENTIAL_BPS' as const,
    unit: 'GAME_MINUTES' as const,
  },
} as const;

export const WORLD_CONDITION_EFFECTS = Object.keys(WORLD_CONDITION_EFFECT_REGISTRY) as Array<keyof typeof WORLD_CONDITION_EFFECT_REGISTRY>;

export type WorldConditionEffect = typeof WORLD_CONDITION_EFFECTS[number];

export type WorldConditionExposureReason = 'EARTHWIDE' | 'CORPORATION_AFFILIATION' | 'NOT_APPLICABLE';

export type WorldConditionSnapshotCondition = {
  id: string;
  code: string;
  title: string;
  description: string;
  source: { type: string; id: string };
  scope: { type: WorldConditionScope; id: string | null };
  severity: string;
  definitionVersion: string;
  effects: Array<{ type: WorldConditionEffect; target: string; modifierBps: number; order: number }>;
  effectiveFromGameDay: number;
  effectiveToGameDay: number | null;
  effective: boolean;
  appliesToViewer: boolean;
  exposureReason: WorldConditionExposureReason;
};

export type WorldConditionsSnapshot = {
  ok: true;
  status: 'AVAILABLE';
  worldState: 'STABLE' | 'ACTIVE';
  authoritativeGameDay: number;
  snapshotVersion: string;
  rulesVersion: string;
  globalConditionCount: number;
  viewerApplicableConditionCount: number;
  conditions: WorldConditionSnapshotCondition[];
  generatedFrom: 'postgres-canonical-facts';
};

export function worldConditionEffectMetadata(effect: string) {
  return WORLD_CONDITION_EFFECT_REGISTRY[effect as WorldConditionEffect] ?? null;
}

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
