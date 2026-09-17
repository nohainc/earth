import { validateProgressiveBrackets, type ProgressiveBracket } from './v5-progressive.ts';

export type ConstitutionalValueType = 'BOOLEAN' | 'INTEGER' | 'CREDIT_UNITS' | 'RATE_BPS' | 'ENUM' | 'GAME_DAYS' | 'RESOURCE_UNITS' | 'PROGRESSIVE_SCHEDULE_REF' | 'POLICY_REFERENCE';
export type ConstitutionalAuthorityModel = 'EARTH_LOCKED' | 'EARTH_DEFAULT_CORPORATION_OVERRIDE' | 'CORPORATION_LOCAL';

export type ConstitutionalRuleDefinition = {
  code: string;
  articleCode: string;
  valueType: ConstitutionalValueType;
  authorityModel: ConstitutionalAuthorityModel;
  policyGroup: string;
  allowedValues?: readonly string[];
};

export const CONSTITUTIONAL_RULE_DEFINITIONS: readonly ConstitutionalRuleDefinition[] = [
  { code: 'EARTH.CAPACITY.STANDARD', articleCode: 'TERRITORY_CAPACITY', valueType: 'INTEGER', authorityModel: 'EARTH_LOCKED', policyGroup: 'CAPACITY_POLICY' },
  { code: 'EARTH.CAPACITY.BASE_RATE', articleCode: 'TERRITORY_CAPACITY', valueType: 'CREDIT_UNITS', authorityModel: 'EARTH_LOCKED', policyGroup: 'CAPACITY_POLICY' },
  { code: 'EARTH.CAPACITY.PROGRESSIVE_SCHEDULE', articleCode: 'TERRITORY_CAPACITY', valueType: 'PROGRESSIVE_SCHEDULE_REF', authorityModel: 'EARTH_LOCKED', policyGroup: 'CAPACITY_POLICY' },
  { code: 'EARTH.CAPACITY.HOUSE_PROGRESSIVE_SCHEDULE', articleCode: 'TERRITORY_CAPACITY', valueType: 'PROGRESSIVE_SCHEDULE_REF', authorityModel: 'EARTH_LOCKED', policyGroup: 'CAPACITY_POLICY' },
  { code: 'CORPORATION.HOUSE_CAPACITY.BASE_RATE', articleCode: 'TERRITORY_CAPACITY', valueType: 'CREDIT_UNITS', authorityModel: 'EARTH_DEFAULT_CORPORATION_OVERRIDE', policyGroup: 'HOUSE_CAPACITY_POLICY' },
  { code: 'CORPORATION.ADMISSION_POLICY', articleCode: 'CORPORATION_GOVERNANCE', valueType: 'ENUM', authorityModel: 'CORPORATION_LOCAL', policyGroup: 'ADMISSION_POLICY', allowedValues: ['OPEN', 'APPROVAL', 'INVITE_ONLY'] },
  { code: 'CORPORATION.GOVERNANCE.POLICY_QUORUM_BPS', articleCode: 'CORPORATION_GOVERNANCE', valueType: 'RATE_BPS', authorityModel: 'EARTH_DEFAULT_CORPORATION_OVERRIDE', policyGroup: 'GOVERNANCE_POLICY' },
  { code: 'CORPORATION.GOVERNANCE.POLICY_APPROVAL_BPS', articleCode: 'CORPORATION_GOVERNANCE', valueType: 'RATE_BPS', authorityModel: 'EARTH_DEFAULT_CORPORATION_OVERRIDE', policyGroup: 'GOVERNANCE_POLICY' },
  { code: 'CORPORATION.GOVERNANCE.VOTING_PERIOD_DAYS', articleCode: 'CORPORATION_GOVERNANCE', valueType: 'GAME_DAYS', authorityModel: 'EARTH_DEFAULT_CORPORATION_OVERRIDE', policyGroup: 'GOVERNANCE_POLICY' },
  { code: 'CORPORATION.GOVERNANCE.IMPLEMENTATION_DELAY_DAYS', articleCode: 'CORPORATION_GOVERNANCE', valueType: 'GAME_DAYS', authorityModel: 'EARTH_DEFAULT_CORPORATION_OVERRIDE', policyGroup: 'GOVERNANCE_POLICY' },
  { code: 'EARTH.HOUSE_INCOME_TAX', articleCode: 'TAXATION', valueType: 'PROGRESSIVE_SCHEDULE_REF', authorityModel: 'EARTH_LOCKED', policyGroup: 'EARTH_HOUSE_INCOME_TAX' },
  { code: 'EARTH.MARKET.TRANSACTION_TAX_RATE', articleCode: 'TAXATION', valueType: 'RATE_BPS', authorityModel: 'EARTH_LOCKED', policyGroup: 'EARTH_MARKET_TAX' },
  { code: 'CORPORATION.HOUSE_INCOME_TAX', articleCode: 'TAXATION', valueType: 'PROGRESSIVE_SCHEDULE_REF', authorityModel: 'CORPORATION_LOCAL', policyGroup: 'CORPORATION_HOUSE_INCOME_TAX' },
  { code: 'CORPORATION.TAX.INCOME_RATE', articleCode: 'TAXATION', valueType: 'RATE_BPS', authorityModel: 'CORPORATION_LOCAL', policyGroup: 'CORPORATION:TAXATION' },
  { code: 'CORPORATION.TAX.SALES_RATE', articleCode: 'TAXATION', valueType: 'RATE_BPS', authorityModel: 'CORPORATION_LOCAL', policyGroup: 'CORPORATION:TAXATION' },
  { code: 'CORPORATION.TAX.CORPORATE_RATE', articleCode: 'TAXATION', valueType: 'RATE_BPS', authorityModel: 'CORPORATION_LOCAL', policyGroup: 'CORPORATION:TAXATION' },
  { code: 'CORPORATION.TAX.PROPERTY_RATE', articleCode: 'TAXATION', valueType: 'RATE_BPS', authorityModel: 'CORPORATION_LOCAL', policyGroup: 'CORPORATION:TAXATION' },
];

export type ConstitutionalRuleValue = boolean | bigint | number | string | ProgressiveBracket[];
export type EffectiveRuleSet = Record<string, ConstitutionalRuleValue>;

export function getConstitutionalRuleDefinition(code: string): ConstitutionalRuleDefinition {
  const found = CONSTITUTIONAL_RULE_DEFINITIONS.find((item) => item.code === code);
  if (!found) throw new Error(`Unknown constitutional rule: ${code}`);
  return found;
}

export function validateConstitutionalRuleValue(code: string, value: unknown): void {
  const rule = getConstitutionalRuleDefinition(code);
  if (rule.valueType === 'BOOLEAN') {
    if (typeof value !== 'boolean') throw new Error(`Invalid value for constitutional rule ${code}`);
    return;
  }
  if (rule.valueType === 'CREDIT_UNITS' || rule.valueType === 'INTEGER' || rule.valueType === 'RATE_BPS' || rule.valueType === 'GAME_DAYS' || rule.valueType === 'RESOURCE_UNITS') {
    const parsed = typeof value === 'bigint' ? value : BigInt(String(value ?? ''));
    if (parsed < 0n || (rule.valueType === 'INTEGER' && parsed === 0n) || (rule.valueType === 'RATE_BPS' && parsed > 10000n)) throw new Error(`Invalid value for constitutional rule ${code}`);
    return;
  }
  if (rule.valueType === 'ENUM') {
    if (typeof value !== 'string' || !rule.allowedValues?.includes(value)) throw new Error(`Invalid value for constitutional rule ${code}`);
    return;
  }
  if (rule.valueType === 'PROGRESSIVE_SCHEDULE_REF' && !Array.isArray(value) && (typeof value !== 'string' || value.trim().length === 0)) throw new Error(`Invalid value for constitutional rule ${code}`);
  if ((rule.valueType === 'POLICY_REFERENCE' || rule.valueType === 'PROGRESSIVE_SCHEDULE_REF') && Array.isArray(value)) validateProgressiveBrackets(value as ProgressiveBracket[]);
  if (rule.valueType === 'POLICY_REFERENCE' && (typeof value !== 'string' || value.trim().length === 0)) throw new Error(`Invalid value for constitutional rule ${code}`);
}

export function resolveConstitutionalRuleSet(input: {
  earth: Readonly<EffectiveRuleSet>;
  corporation?: Readonly<EffectiveRuleSet>;
}): EffectiveRuleSet {
  const resolved: EffectiveRuleSet = {};
  for (const rule of CONSTITUTIONAL_RULE_DEFINITIONS) {
    const earthValue = input.earth[rule.code];
    const corporationValue = input.corporation?.[rule.code];
    if (rule.authorityModel === 'EARTH_LOCKED' && earthValue !== undefined) resolved[rule.code] = earthValue;
    else if (rule.authorityModel === 'EARTH_DEFAULT_CORPORATION_OVERRIDE' && (corporationValue !== undefined || earthValue !== undefined)) resolved[rule.code] = corporationValue ?? earthValue;
    else if (corporationValue !== undefined) resolved[rule.code] = corporationValue;
  }
  return resolved;
}
