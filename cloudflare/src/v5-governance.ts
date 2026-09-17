import { calculateProgressiveCharge, validateProgressiveBrackets, type ProgressiveBracket } from './v5-progressive.ts';
import { validateConstitutionalRuleValue } from './v5-constitution.ts';

export type V5GovernanceActionType =
  | 'CONSTITUTION_AMENDMENT'
  | 'EARTH_CAPACITY_POLICY'
  | 'CORPORATION_HOUSE_RATE'
  | 'PROGRESSIVE_SCHEDULE'
  | 'CORPORATION_ADMISSION_POLICY';

export type V5GovernanceAction = {
  actionType: V5GovernanceActionType;
  effectiveFromGameDay: number;
  earthBaseRateUnits?: bigint;
  standardTerritoryCapacityUnits?: bigint;
  corporationId?: string;
  houseBaseRateUnits?: bigint;
  admissionPolicy?: 'OPEN' | 'APPROVAL' | 'INVITE_ONLY';
  scheduleId?: string;
  authorityInstitutionId?: string;
  scheduleCode?: string;
  scheduleBasisType?: 'EARTH_CORPORATION_CAPACITY' | 'CORPORATION_HOUSE_CAPACITY' | 'HOUSE_INCOME_TAX';
  brackets?: ProgressiveBracket[];
  changes?: Array<{ ruleCode: string; value?: unknown; clearOverride?: boolean; baseVersionId?: string }>;
};

export type ProgressivePolicyPreview = {
  current: { quantity: bigint; totalCharge: bigint; marginalCharge: bigint };
  proposed: { quantity: bigint; totalCharge: bigint; marginalCharge: bigint };
  delta: bigint;
};

function positiveInteger(value: unknown, field: string): bigint {
  const parsed = typeof value === 'bigint' ? value : BigInt(String(value ?? ''));
  if (parsed < 0n) throw new Error(`${field} must be a non-negative integer`);
  return parsed;
}

export function validateV5FutureEffectiveDay(effectiveFromGameDay: number, currentGameDay: number): void {
  if (!Number.isInteger(effectiveFromGameDay) || effectiveFromGameDay < currentGameDay + 1) {
    throw new Error('V5 policy changes must take effect on a future game day');
  }
}

export function validateV5GovernanceAction(action: V5GovernanceAction, currentGameDay: number): void {
  validateV5FutureEffectiveDay(action.effectiveFromGameDay, currentGameDay);
  if (action.actionType === 'CONSTITUTION_AMENDMENT') {
    if (!action.changes?.length) throw new Error('Constitution amendment requires at least one rule change');
    const codes = new Set<string>();
    for (const change of action.changes) {
      if (!change.ruleCode?.trim() || codes.has(change.ruleCode)) throw new Error('Constitution amendment contains duplicate or missing rule codes');
      codes.add(change.ruleCode);
      if (change.clearOverride) continue;
      validateConstitutionalRuleValue(change.ruleCode, change.value);
    }
    return;
  }
  if (action.actionType === 'EARTH_CAPACITY_POLICY') {
    positiveInteger(action.earthBaseRateUnits, 'EARTH base capacity rate');
    if (!action.standardTerritoryCapacityUnits || action.standardTerritoryCapacityUnits <= 0n) throw new Error('Standard Territory capacity must be positive');
    return;
  }
  if (action.actionType === 'CORPORATION_HOUSE_RATE') {
    if (!action.corporationId?.trim()) throw new Error('Corporation is required');
    positiveInteger(action.houseBaseRateUnits, 'Corporation House capacity rate');
    return;
  }
  if (action.actionType === 'CORPORATION_ADMISSION_POLICY') {
    if (!action.corporationId?.trim()) throw new Error('Corporation is required');
    if (!action.admissionPolicy || !['OPEN', 'APPROVAL', 'INVITE_ONLY'].includes(action.admissionPolicy)) throw new Error('Admission policy must be OPEN, APPROVAL, or INVITE_ONLY');
    return;
  }
  if (!action.scheduleCode?.trim() || !action.authorityInstitutionId?.trim() || !action.scheduleBasisType || !action.brackets?.length) throw new Error('Progressive schedule code, authority, basis, and brackets are required');
  validateProgressiveBrackets(action.brackets);
}

export function previewProgressivePolicyChange(input: {
  quantities: bigint[];
  baseRate: bigint;
  currentBrackets: ProgressiveBracket[];
  proposedBrackets: ProgressiveBracket[];
}): ProgressivePolicyPreview[] {
  validateProgressiveBrackets(input.currentBrackets);
  validateProgressiveBrackets(input.proposedBrackets);
  return input.quantities.map((quantity) => {
    if (quantity < 0n) throw new Error('Preview quantities must be non-negative');
    const current = calculateProgressiveCharge({ quantity, baseRate: input.baseRate, brackets: input.currentBrackets });
    const proposed = calculateProgressiveCharge({ quantity, baseRate: input.baseRate, brackets: input.proposedBrackets });
    const currentBefore = calculateProgressiveCharge({ quantity: quantity === 0n ? 0n : quantity - 1n, baseRate: input.baseRate, brackets: input.currentBrackets });
    const proposedBefore = calculateProgressiveCharge({ quantity: quantity === 0n ? 0n : quantity - 1n, baseRate: input.baseRate, brackets: input.proposedBrackets });
    return {
      current: { quantity, totalCharge: current.totalCharge, marginalCharge: current.totalCharge - currentBefore.totalCharge },
      proposed: { quantity, totalCharge: proposed.totalCharge, marginalCharge: proposed.totalCharge - proposedBefore.totalCharge },
      delta: proposed.totalCharge - current.totalCharge,
    };
  });
}
