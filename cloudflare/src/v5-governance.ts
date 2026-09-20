import { calculateProgressiveCharge, validateProgressiveBrackets, type ProgressiveBracket } from './v5-progressive.ts';
import { getConstitutionalRuleDefinition, validateConstitutionalRuleValue, type EffectiveRuleSet } from './v5-constitution.ts';
import { validateInitiativeOutcome } from './initiative-outcomes.ts';

export type V5GovernanceActionType =
  | 'CONSTITUTION_AMENDMENT'
  | 'CORPORATION_PUBLIC_CONSTRUCTION'
  | 'CORPORATION_BUILDING_RESEARCH'
  | 'CORPORATION_SCALE_RESEARCH'
  | 'EARTH_TECHNOLOGY_FRONTIER'
  | 'INITIATIVE_CREATE'
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
  domainId?: string;
  generationNumber?: number;
  researchCreditCostUnits?: bigint;
  researchResourceCosts?: Record<string, string>;
  buildingType?: string;
  targetTier?: number;
  territoryId?: string;
  name?: string;
  generation?: number;
  scaleCapability?: 'SCALE_COMMERCIAL' | 'SCALE_INDUSTRIAL' | 'SCALE_STRATEGIC';
  initiativeType?: 'PROGRAM' | 'PUBLIC_PROJECT' | 'EMERGENCY' | 'COMMONS';
  programType?: 'TECHNOLOGY' | 'COMMONS' | 'EMERGENCY';
  initiativeDescription?: string;
  fundingTargetUnits?: bigint;
  treasuryAuthorizedUnits?: bigint;
  matchingPolicy?: 'NONE' | 'LINEAR_MATCH' | 'BREADTH_MATCH';
  matchingCapUnits?: bigint;
  fundingDeadlineGameDay?: number;
  fundingModel?: 'TREASURY' | 'CROWDFUND' | 'MATCHED' | 'MIXED';
  executionModel?: 'FUNDING_ONLY' | 'TIMED_PROGRAM' | 'PUBLIC_WORK';
  executionDurationGameDays?: number;
  executionResourceRequirements?: Record<string, string>;
  progressModel?: 'FUNDING_ONLY' | 'TIME' | 'TIME_AND_RESOURCES';
  outcome?: Record<string, unknown>;
  /** Physical placement/capacity metadata; never an authority or beneficiary scope. */
  physicalTarget?: Record<string, unknown>;
};

export type ProgressivePolicyPreview = {
  current: { quantity: bigint; totalCharge: bigint; marginalCharge: bigint };
  proposed: { quantity: bigint; totalCharge: bigint; marginalCharge: bigint };
  delta: bigint;
};

export type ConstitutionAmendmentPreview = {
  currentRules: EffectiveRuleSet;
  proposedRules: EffectiveRuleSet;
  changes: Array<{
    ruleCode: string;
    articleCode: string;
    policyGroup: string;
    valueType: string;
    currentValue: unknown;
    proposedValue: unknown;
    clearedOverride: boolean;
  }>;
};

export type V5GovernanceTiming = {
  votingStartGameDay: number;
  votingEndGameDay: number;
  implementationDelayDays: number;
  earliestValidEffectiveGameDay: number;
};

export function deriveV5GovernanceTiming(
  currentGameDay: number,
  votingPeriodDays: number,
  implementationDelayDays: number,
): V5GovernanceTiming {
  const votingStartGameDay = currentGameDay + 1;
  const votingEndGameDay = votingStartGameDay + votingPeriodDays;
  return {
    votingStartGameDay,
    votingEndGameDay,
    implementationDelayDays,
    earliestValidEffectiveGameDay: votingEndGameDay + implementationDelayDays + 1,
  };
}

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
  if (action.actionType === 'INITIATIVE_CREATE') {
    if (!action.initiativeType || !['PROGRAM', 'PUBLIC_PROJECT', 'EMERGENCY', 'COMMONS'].includes(action.initiativeType)) throw new Error('Initiative type is invalid');
    if (!action.name?.trim() || action.name.trim().length > 120) throw new Error('Initiative name is required and must be at most 120 characters');
    if (!action.initiativeDescription?.trim()) throw new Error('Initiative description is required');
    validateInitiativeOutcome(action.outcome);
    if (action.physicalTarget !== undefined && (typeof action.physicalTarget !== 'object' || action.physicalTarget === null || Array.isArray(action.physicalTarget))) throw new Error('Initiative physical target must be an object');
    if ('beneficiaryType' in action || 'beneficiaryId' in action || 'recipientAccountId' in action) throw new Error('Initiatives use Earth or Corporation governance scope; beneficiary and recipient authority fields are not allowed');
    if (action.initiativeType === 'PROGRAM' && (!action.programType || !['TECHNOLOGY', 'COMMONS', 'EMERGENCY'].includes(action.programType))) throw new Error('Program initiatives require a valid program type');
    if (action.initiativeType !== 'PROGRAM' && action.programType != null) throw new Error('Only PROGRAM initiatives may specify a program type');
    if (positiveInteger(action.fundingTargetUnits, 'Initiative funding target') <= 0n) throw new Error('Initiative funding target must be positive');
    positiveInteger(action.treasuryAuthorizedUnits ?? 0n, 'Initiative treasury authorization');
    positiveInteger(action.matchingCapUnits ?? 0n, 'Initiative matching cap');
    if (!action.fundingModel || !['TREASURY', 'CROWDFUND', 'MATCHED', 'MIXED'].includes(action.fundingModel)) throw new Error('Initiative funding model is invalid');
    if (!action.executionModel || !['FUNDING_ONLY', 'TIMED_PROGRAM', 'PUBLIC_WORK'].includes(action.executionModel)) throw new Error('Initiative execution model is invalid');
    const defaultProgressModel = action.initiativeType === 'PROGRAM' ? 'TIME' : 'FUNDING_ONLY';
    const progressModel = action.progressModel ?? defaultProgressModel;
    if (!['FUNDING_ONLY', 'TIME', 'TIME_AND_RESOURCES'].includes(progressModel)) throw new Error('Initiative progress model is invalid');
    if (action.initiativeType === 'PROGRAM') {
      if (action.executionModel !== 'TIMED_PROGRAM') throw new Error('Programs require timed execution');
      if (!Number.isInteger(action.executionDurationGameDays) || Number(action.executionDurationGameDays) <= 0) throw new Error('Programs require a positive execution duration');
      if (!['TIME', 'TIME_AND_RESOURCES'].includes(progressModel)) throw new Error('Programs require time-based progress');
    } else if (progressModel === 'FUNDING_ONLY' && action.executionDurationGameDays != null) {
      throw new Error('Funding-only initiatives cannot declare an execution duration');
    }
    if (action.executionResourceRequirements != null) {
      if (typeof action.executionResourceRequirements !== 'object' || Array.isArray(action.executionResourceRequirements)) throw new Error('Execution resource requirements must be an object');
      for (const [resource, quantity] of Object.entries(action.executionResourceRequirements)) {
        if (!resource.trim() || !/^\d+$/.test(String(quantity)) || BigInt(String(quantity)) <= 0n) throw new Error('Execution resource requirements must contain positive integer quantities');
      }
    }
    if (!action.matchingPolicy || !['NONE', 'LINEAR_MATCH', 'BREADTH_MATCH'].includes(action.matchingPolicy)) throw new Error('Initiative matching policy is invalid');
    if (action.matchingPolicy === 'NONE' && (action.matchingCapUnits ?? 0n) !== 0n) throw new Error('Matching cap must be zero when matching is disabled');
    if (!Number.isInteger(action.fundingDeadlineGameDay) || Number(action.fundingDeadlineGameDay) < currentGameDay + 1) throw new Error('Initiative funding deadline must be a future game day');
    return;
  }
  if (action.actionType === 'CORPORATION_PUBLIC_CONSTRUCTION') {
    if (!action.corporationId?.trim()) throw new Error('Corporation is required');
    if (!action.buildingType?.trim()) throw new Error('Building type is required');
    if (action.generation != null && (!Number.isInteger(action.generation) || action.generation < 1)) {
      throw new Error('Generation must be a positive integer');
    }
    return;
  }
  if (action.actionType === 'CORPORATION_BUILDING_RESEARCH') {
    if (!action.corporationId?.trim()) throw new Error('Corporation is required');
    if (!action.buildingType?.trim()) throw new Error('Building family is required');
    if (!Number.isInteger(action.targetTier) || Number(action.targetTier) < 2) throw new Error('Target building tier must be at least 2');
    if (action.researchCreditCostUnits != null) positiveInteger(action.researchCreditCostUnits, 'Building research CREDIT cost');
    return;
  }
  if (action.actionType === 'CORPORATION_SCALE_RESEARCH') {
    if (!action.corporationId?.trim()) throw new Error('Corporation is required');
    if (!action.scaleCapability || !['SCALE_COMMERCIAL', 'SCALE_INDUSTRIAL', 'SCALE_STRATEGIC'].includes(action.scaleCapability)) {
      throw new Error('Valid scale capability is required (SCALE_COMMERCIAL, SCALE_INDUSTRIAL, or SCALE_STRATEGIC)');
    }
    positiveInteger(action.researchCreditCostUnits ?? 0n, 'Research CREDIT cost');
    if (action.researchResourceCosts && Object.values(action.researchResourceCosts).some((value) => { try { return BigInt(value) < 0n; } catch (_error) { return true; } })) {
      throw new Error('Research resource costs must be non-negative integers');
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
  if (action.actionType === 'EARTH_TECHNOLOGY_FRONTIER') {
    if (!action.domainId?.trim()) throw new Error('Technology domain is required');
    if (!Number.isInteger(action.generationNumber) || Number(action.generationNumber) < 1) throw new Error('Technology generation must be positive');
    positiveInteger(action.researchCreditCostUnits ?? 0n, 'Research CREDIT cost');
    if (action.researchResourceCosts && Object.values(action.researchResourceCosts).some((value) => { try { return BigInt(value) < 0n; } catch (_error) { return true; } })) throw new Error('Research resource costs must be non-negative integers');
    return;
  }
  if (!action.scheduleCode?.trim() || !action.authorityInstitutionId?.trim() || !action.scheduleBasisType || !action.brackets?.length) throw new Error('Progressive schedule code, authority, basis, and brackets are required');
  validateProgressiveBrackets(action.brackets);
}

/**
 * Build the canonical, side-effect-free impact view for a Constitution
 * amendment. Callers provide the already-resolved rule set for the target
 * authority; this keeps preview semantics identical to activation semantics
 * without allowing the preview endpoint to become a mutation path.
 */
export function previewConstitutionAmendment(input: {
  currentRules: Readonly<EffectiveRuleSet>;
  fallbackRules?: Readonly<EffectiveRuleSet>;
  changes: ReadonlyArray<{ ruleCode: string; value?: unknown; clearOverride?: boolean }>;
}): ConstitutionAmendmentPreview {
  if (input.changes.length === 0) throw new Error('Constitution amendment requires at least one rule change');
  const proposedRules: EffectiveRuleSet = { ...input.currentRules };
  const seen = new Set<string>();
  const changes = input.changes.map((change) => {
    const ruleCode = change.ruleCode?.trim();
    if (!ruleCode || seen.has(ruleCode)) throw new Error('Constitution amendment contains duplicate or missing rule codes');
    seen.add(ruleCode);
    const definition = getConstitutionalRuleDefinition(ruleCode);
    const currentValue = input.currentRules[ruleCode];
    if (change.clearOverride) {
      const fallbackValue = input.fallbackRules?.[ruleCode];
      if (fallbackValue === undefined) delete proposedRules[ruleCode];
      else proposedRules[ruleCode] = fallbackValue;
    } else {
      validateConstitutionalRuleValue(ruleCode, change.value);
      proposedRules[ruleCode] = change.value as EffectiveRuleSet[string];
    }
    return {
      ruleCode,
      articleCode: definition.articleCode,
      valueType: definition.valueType,
      policyGroup: definition.policyGroup,
      currentValue,
      proposedValue: proposedRules[ruleCode],
      clearedOverride: Boolean(change.clearOverride),
    };
  });
  return { currentRules: { ...input.currentRules }, proposedRules, changes };
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
