import { validateProgressiveBrackets, type ProgressiveBracket } from './v5-progressive.ts';
import { parseCreditAmount } from './money.ts';

export type ConstitutionalValueType = 'BOOLEAN' | 'INTEGER' | 'CREDIT_UNITS' | 'RATE_BPS' | 'ENUM' | 'GAME_DAYS' | 'RESOURCE_UNITS' | 'PROGRESSIVE_SCHEDULE_REF' | 'POLICY_REFERENCE';
export type ConstitutionalAuthorityModel = 'EARTH_LOCKED' | 'EARTH_DEFAULT_CORPORATION_OVERRIDE' | 'CORPORATION_LOCAL';
export type ConstitutionalAmendmentClass = 'FOUNDATIONAL' | 'POLICY' | 'LOCAL_POLICY' | 'OPERATIONAL';

export type ConstitutionalRuleDefinition = {
  code: string;
  articleCode: string;
  valueType: ConstitutionalValueType;
  authorityModel: ConstitutionalAuthorityModel;
  policyGroup: string;
  calculationKey: string;
  amendmentClass: ConstitutionalAmendmentClass;
  allowedValues?: readonly string[];
  displayName: string;
  description: string;
  articleLabel: string;
  order: number;
  inputHint: string;
  displayHint: string;
};

export type ConstitutionalInputSpec = {
  inputKind: 'DECIMAL_CREDIT' | 'PERCENTAGE' | 'INTEGER' | 'RESOURCE_QUANTITY' | 'ENUM' | 'BOOLEAN' | 'SCHEDULE_ID';
  min: string | null;
  max: string | null;
  step: string | null;
  allowedValues: readonly string[];
};

const BASE_CONSTITUTIONAL_RULE_DEFINITIONS = [
  { code: 'EARTH.CAPACITY.STANDARD', articleCode: 'TERRITORY_CAPACITY', valueType: 'INTEGER', authorityModel: 'EARTH_LOCKED', policyGroup: 'CAPACITY_POLICY', calculationKey: 'earth.capacity.standard', amendmentClass: 'POLICY' },
  { code: 'EARTH.CAPACITY.BASE_RATE', articleCode: 'TERRITORY_CAPACITY', valueType: 'CREDIT_UNITS', authorityModel: 'EARTH_LOCKED', policyGroup: 'CAPACITY_POLICY', calculationKey: 'earth.capacity.base_rate', amendmentClass: 'POLICY' },
  { code: 'EARTH.CAPACITY.PROGRESSIVE_SCHEDULE', articleCode: 'TERRITORY_CAPACITY', valueType: 'PROGRESSIVE_SCHEDULE_REF', authorityModel: 'EARTH_LOCKED', policyGroup: 'CAPACITY_POLICY', calculationKey: 'earth.capacity.progressive_schedule', amendmentClass: 'POLICY' },
  { code: 'EARTH.CAPACITY.HOUSE_PROGRESSIVE_SCHEDULE', articleCode: 'TERRITORY_CAPACITY', valueType: 'PROGRESSIVE_SCHEDULE_REF', authorityModel: 'EARTH_LOCKED', policyGroup: 'CAPACITY_POLICY', calculationKey: 'earth.capacity.house_progressive_schedule', amendmentClass: 'POLICY' },
  { code: 'CORPORATION.HOUSE_CAPACITY.BASE_RATE', articleCode: 'TERRITORY_CAPACITY', valueType: 'CREDIT_UNITS', authorityModel: 'EARTH_DEFAULT_CORPORATION_OVERRIDE', policyGroup: 'HOUSE_CAPACITY_POLICY', calculationKey: 'corporation.house_capacity.base_rate', amendmentClass: 'LOCAL_POLICY' },
  { code: 'CORPORATION.ADMISSION_POLICY', articleCode: 'CORPORATION_GOVERNANCE', valueType: 'ENUM', authorityModel: 'CORPORATION_LOCAL', policyGroup: 'ADMISSION_POLICY', calculationKey: 'corporation.admission_policy', amendmentClass: 'LOCAL_POLICY', allowedValues: ['OPEN', 'APPROVAL', 'INVITE_ONLY'] },
  { code: 'EARTH.GOVERNANCE.POLICY_QUORUM_BPS', articleCode: 'EARTH_GOVERNANCE', valueType: 'RATE_BPS', authorityModel: 'EARTH_LOCKED', policyGroup: 'EARTH_GOVERNANCE_POLICY', calculationKey: 'earth.governance.policy_quorum_bps', amendmentClass: 'POLICY' },
  { code: 'EARTH.GOVERNANCE.POLICY_APPROVAL_BPS', articleCode: 'EARTH_GOVERNANCE', valueType: 'RATE_BPS', authorityModel: 'EARTH_LOCKED', policyGroup: 'EARTH_GOVERNANCE_POLICY', calculationKey: 'earth.governance.policy_approval_bps', amendmentClass: 'POLICY' },
  { code: 'EARTH.GOVERNANCE.VOTING_PERIOD_DAYS', articleCode: 'EARTH_GOVERNANCE', valueType: 'GAME_DAYS', authorityModel: 'EARTH_LOCKED', policyGroup: 'EARTH_GOVERNANCE_POLICY', calculationKey: 'earth.governance.voting_period_days', amendmentClass: 'POLICY' },
  { code: 'EARTH.GOVERNANCE.IMPLEMENTATION_DELAY_DAYS', articleCode: 'EARTH_GOVERNANCE', valueType: 'GAME_DAYS', authorityModel: 'EARTH_LOCKED', policyGroup: 'EARTH_GOVERNANCE_POLICY', calculationKey: 'earth.governance.implementation_delay_days', amendmentClass: 'POLICY' },
  { code: 'EARTH.SUCCESSION.COST_UNITS', articleCode: 'SUCCESSION', valueType: 'CREDIT_UNITS', authorityModel: 'EARTH_LOCKED', policyGroup: 'SUCCESSION_POLICY', calculationKey: 'earth.succession.cost_units', amendmentClass: 'POLICY' },
  { code: 'EARTH.SUCCESSION.COST_BPS', articleCode: 'SUCCESSION', valueType: 'RATE_BPS', authorityModel: 'EARTH_LOCKED', policyGroup: 'SUCCESSION_POLICY', calculationKey: 'earth.succession.cost_bps', amendmentClass: 'POLICY' },
  { code: 'EARTH.SUCCESSION.TRANSITION_DAYS', articleCode: 'SUCCESSION', valueType: 'GAME_DAYS', authorityModel: 'EARTH_LOCKED', policyGroup: 'SUCCESSION_POLICY', calculationKey: 'earth.succession.transition_days', amendmentClass: 'POLICY' },
  { code: 'CORPORATION.GOVERNANCE.POLICY_QUORUM_BPS', articleCode: 'CORPORATION_GOVERNANCE', valueType: 'RATE_BPS', authorityModel: 'EARTH_DEFAULT_CORPORATION_OVERRIDE', policyGroup: 'GOVERNANCE_POLICY', calculationKey: 'corporation.governance.policy_quorum_bps', amendmentClass: 'POLICY' },
  { code: 'CORPORATION.GOVERNANCE.POLICY_APPROVAL_BPS', articleCode: 'CORPORATION_GOVERNANCE', valueType: 'RATE_BPS', authorityModel: 'EARTH_DEFAULT_CORPORATION_OVERRIDE', policyGroup: 'GOVERNANCE_POLICY', calculationKey: 'corporation.governance.policy_approval_bps', amendmentClass: 'POLICY' },
  { code: 'CORPORATION.GOVERNANCE.VOTING_PERIOD_DAYS', articleCode: 'CORPORATION_GOVERNANCE', valueType: 'GAME_DAYS', authorityModel: 'EARTH_DEFAULT_CORPORATION_OVERRIDE', policyGroup: 'GOVERNANCE_POLICY', calculationKey: 'corporation.governance.voting_period_days', amendmentClass: 'POLICY' },
  { code: 'CORPORATION.GOVERNANCE.IMPLEMENTATION_DELAY_DAYS', articleCode: 'CORPORATION_GOVERNANCE', valueType: 'GAME_DAYS', authorityModel: 'EARTH_DEFAULT_CORPORATION_OVERRIDE', policyGroup: 'GOVERNANCE_POLICY', calculationKey: 'corporation.governance.implementation_delay_days', amendmentClass: 'POLICY' },
  { code: 'EARTH.HOUSE_INCOME_TAX', articleCode: 'TAXATION', valueType: 'PROGRESSIVE_SCHEDULE_REF', authorityModel: 'EARTH_LOCKED', policyGroup: 'EARTH_HOUSE_INCOME_TAX', calculationKey: 'earth.house_income_tax', amendmentClass: 'POLICY' },
  { code: 'EARTH.TAX.BASIC_LEVY_RATE', articleCode: 'TAXATION', valueType: 'RATE_BPS', authorityModel: 'EARTH_LOCKED', policyGroup: 'EARTH_BASIC_LEVY', calculationKey: 'earth.tax.basic_levy_rate', amendmentClass: 'POLICY' },
  { code: 'EARTH.MARKET.TRANSACTION_TAX_RATE', articleCode: 'TAXATION', valueType: 'RATE_BPS', authorityModel: 'EARTH_LOCKED', policyGroup: 'EARTH_MARKET_TAX', calculationKey: 'earth.market.transaction_tax_rate', amendmentClass: 'POLICY' },
  { code: 'CORPORATION.HOUSE_INCOME_TAX', articleCode: 'TAXATION', valueType: 'PROGRESSIVE_SCHEDULE_REF', authorityModel: 'CORPORATION_LOCAL', policyGroup: 'CORPORATION_HOUSE_INCOME_TAX', calculationKey: 'corporation.house_income_tax', amendmentClass: 'LOCAL_POLICY' },
  { code: 'CORPORATION.TAX.INCOME_RATE', articleCode: 'TAXATION', valueType: 'RATE_BPS', authorityModel: 'CORPORATION_LOCAL', policyGroup: 'CORPORATION:TAXATION', calculationKey: 'corporation.tax.income_rate', amendmentClass: 'LOCAL_POLICY' },
  { code: 'CORPORATION.TAX.SALES_RATE', articleCode: 'TAXATION', valueType: 'RATE_BPS', authorityModel: 'CORPORATION_LOCAL', policyGroup: 'CORPORATION:TAXATION', calculationKey: 'corporation.tax.sales_rate', amendmentClass: 'LOCAL_POLICY' },
  { code: 'CORPORATION.TAX.CORPORATE_RATE', articleCode: 'TAXATION', valueType: 'RATE_BPS', authorityModel: 'CORPORATION_LOCAL', policyGroup: 'CORPORATION:TAXATION', calculationKey: 'corporation.tax.corporate_rate', amendmentClass: 'LOCAL_POLICY' },
  { code: 'CORPORATION.TAX.PROPERTY_RATE', articleCode: 'TAXATION', valueType: 'RATE_BPS', authorityModel: 'CORPORATION_LOCAL', policyGroup: 'CORPORATION:TAXATION', calculationKey: 'corporation.tax.property_rate', amendmentClass: 'LOCAL_POLICY' },
] satisfies readonly Omit<ConstitutionalRuleDefinition, 'displayName' | 'description' | 'articleLabel' | 'order' | 'inputHint' | 'displayHint'>[];

type ConstitutionalRulePresentation = Pick<ConstitutionalRuleDefinition, 'displayName' | 'description' | 'articleLabel' | 'order' | 'inputHint' | 'displayHint'>;

const RULE_PRESENTATION: Record<string, ConstitutionalRulePresentation> = {
  'EARTH.CAPACITY.STANDARD': { displayName: 'Standard Capacity Block', description: 'Defines the physical capacity represented by one standard block.', articleLabel: 'CAPACITY & SCARCITY', order: 10, inputHint: 'Whole capacity units', displayHint: 'Capacity units' },
  'EARTH.CAPACITY.BASE_RATE': { displayName: 'Earth Capacity Base Rate', description: 'Base daily CREDIT rate for Earth physical capacity.', articleLabel: 'CAPACITY & SCARCITY', order: 20, inputHint: 'Decimal CREDIT per unit per day', displayHint: 'CREDIT per unit per day' },
  'EARTH.CAPACITY.PROGRESSIVE_SCHEDULE': { displayName: 'Earth Corporation Capacity Schedule', description: 'Progressive schedule applied to Corporation capacity usage.', articleLabel: 'CAPACITY & SCARCITY', order: 30, inputHint: 'Select a published schedule', displayHint: 'Progressive capacity schedule' },
  'EARTH.CAPACITY.HOUSE_PROGRESSIVE_SCHEDULE': { displayName: 'Earth House Capacity Schedule', description: 'Progressive schedule applied to House capacity usage.', articleLabel: 'CAPACITY & SCARCITY', order: 40, inputHint: 'Select a published schedule', displayHint: 'Progressive capacity schedule' },
  'CORPORATION.HOUSE_CAPACITY.BASE_RATE': { displayName: 'House Capacity Base Rate', description: 'Corporation rate charged for member House capacity.', articleLabel: 'CAPACITY & SCARCITY', order: 50, inputHint: 'Decimal CREDIT per unit per day', displayHint: 'CREDIT per unit per day' },
  'CORPORATION.ADMISSION_POLICY': { displayName: 'Corporation Admission Policy', description: 'Controls how Houses may join this Corporation.', articleLabel: 'CORPORATION GOVERNANCE', order: 60, inputHint: 'Select an admission policy', displayHint: 'Admission policy' },
  'EARTH.GOVERNANCE.POLICY_QUORUM_BPS': { displayName: 'Earth Governance Quorum', description: 'Participation required for an Earth governance decision to be valid.', articleLabel: 'EARTH GOVERNANCE', order: 70, inputHint: 'Percentage of the electorate', displayHint: 'Quorum percentage' },
  'EARTH.GOVERNANCE.POLICY_APPROVAL_BPS': { displayName: 'Earth Governance Approval', description: 'Support threshold for an Earth governance decision to pass.', articleLabel: 'EARTH GOVERNANCE', order: 80, inputHint: 'Percentage of decisive votes', displayHint: 'Approval percentage' },
  'EARTH.GOVERNANCE.VOTING_PERIOD_DAYS': { displayName: 'Earth Voting Period', description: 'Number of game days an Earth proposal remains open for voting.', articleLabel: 'EARTH GOVERNANCE', order: 90, inputHint: 'Whole game days', displayHint: 'Game days' },
  'EARTH.GOVERNANCE.IMPLEMENTATION_DELAY_DAYS': { displayName: 'Earth Implementation Delay', description: 'Minimum delay between a passed Earth proposal and its effective day.', articleLabel: 'EARTH GOVERNANCE', order: 100, inputHint: 'Whole game days', displayHint: 'Game days' },
  'EARTH.SUCCESSION.COST_UNITS': { displayName: 'Fixed Succession Cost', description: 'Fixed CREDIT cost applied when House succession is settled.', articleLabel: 'SUCCESSION', order: 110, inputHint: 'Decimal CREDIT amount', displayHint: 'CREDIT' },
  'EARTH.SUCCESSION.COST_BPS': { displayName: 'Succession Percentage Cost', description: 'Percentage cost applied to the House estate during succession.', articleLabel: 'SUCCESSION', order: 120, inputHint: 'Percentage of estate value', displayHint: 'Percentage' },
  'EARTH.SUCCESSION.TRANSITION_DAYS': { displayName: 'Succession Transition Period', description: 'Game days required to complete a House succession transition.', articleLabel: 'SUCCESSION', order: 130, inputHint: 'Whole game days', displayHint: 'Game days' },
  'CORPORATION.GOVERNANCE.POLICY_QUORUM_BPS': { displayName: 'Corporation Governance Quorum', description: 'Participation required for a Corporation governance decision to be valid.', articleLabel: 'CORPORATION GOVERNANCE', order: 140, inputHint: 'Percentage of the electorate', displayHint: 'Quorum percentage' },
  'CORPORATION.GOVERNANCE.POLICY_APPROVAL_BPS': { displayName: 'Corporation Governance Approval', description: 'Support threshold for a Corporation governance decision to pass.', articleLabel: 'CORPORATION GOVERNANCE', order: 150, inputHint: 'Percentage of decisive votes', displayHint: 'Approval percentage' },
  'CORPORATION.GOVERNANCE.VOTING_PERIOD_DAYS': { displayName: 'Corporation Voting Period', description: 'Number of game days a Corporation proposal remains open for voting.', articleLabel: 'CORPORATION GOVERNANCE', order: 160, inputHint: 'Whole game days', displayHint: 'Game days' },
  'CORPORATION.GOVERNANCE.IMPLEMENTATION_DELAY_DAYS': { displayName: 'Corporation Implementation Delay', description: 'Minimum delay between a passed Corporation proposal and its effective day.', articleLabel: 'CORPORATION GOVERNANCE', order: 170, inputHint: 'Whole game days', displayHint: 'Game days' },
  'EARTH.HOUSE_INCOME_TAX': { displayName: 'Earth House Income Tax', description: 'Progressive Earth income-tax schedule applied to Houses.', articleLabel: 'TAXATION & FISCAL', order: 180, inputHint: 'Select a published schedule', displayHint: 'Progressive tax schedule' },
  'EARTH.TAX.BASIC_LEVY_RATE': { displayName: 'Earth Basic Levy', description: 'Earth-wide basic levy rate applied to its canonical tax base.', articleLabel: 'TAXATION & FISCAL', order: 190, inputHint: 'Percentage rate', displayHint: 'Percentage' },
  'EARTH.MARKET.TRANSACTION_TAX_RATE': { displayName: 'Market Transaction Tax', description: 'Earth rate applied to taxable Market transactions.', articleLabel: 'TAXATION & FISCAL', order: 200, inputHint: 'Percentage rate', displayHint: 'Percentage' },
  'CORPORATION.HOUSE_INCOME_TAX': { displayName: 'Corporation House Income Tax', description: 'Corporation income-tax schedule applied to member Houses.', articleLabel: 'TAXATION & FISCAL', order: 210, inputHint: 'Select a published schedule', displayHint: 'Progressive tax schedule' },
  'CORPORATION.TAX.INCOME_RATE': { displayName: 'Corporation Income Tax', description: 'Corporation income-tax rate applied to its canonical tax base.', articleLabel: 'TAXATION & FISCAL', order: 220, inputHint: 'Percentage rate', displayHint: 'Percentage' },
  'CORPORATION.TAX.SALES_RATE': { displayName: 'Corporation Sales Tax', description: 'Corporation sales-tax rate applied to its canonical sales base.', articleLabel: 'TAXATION & FISCAL', order: 230, inputHint: 'Percentage rate', displayHint: 'Percentage' },
  'CORPORATION.TAX.CORPORATE_RATE': { displayName: 'Corporation Corporate Tax', description: 'Corporation tax rate applied to its canonical corporate base.', articleLabel: 'TAXATION & FISCAL', order: 240, inputHint: 'Percentage rate', displayHint: 'Percentage' },
  'CORPORATION.TAX.PROPERTY_RATE': { displayName: 'Corporation Property Tax', description: 'Corporation property-tax rate applied to its canonical property base.', articleLabel: 'TAXATION & FISCAL', order: 250, inputHint: 'Percentage rate', displayHint: 'Percentage' },
};

export const CONSTITUTIONAL_RULE_DEFINITIONS: readonly ConstitutionalRuleDefinition[] = BASE_CONSTITUTIONAL_RULE_DEFINITIONS.map((definition) => {
  const presentation = RULE_PRESENTATION[definition.code];
  if (!presentation) throw new Error(`Missing Constitution presentation metadata: ${definition.code}`);
  return { ...definition, ...presentation };
});

export function assertConstitutionalAmendableRule(code: string): ConstitutionalRuleDefinition {
  const rule = getConstitutionalRuleDefinition(code);
  if (rule.amendmentClass === 'OPERATIONAL') throw new Error(`Operational rule cannot be amended through Constitution: ${code}`);
  return rule;
}

export type ConstitutionalRuleValue = boolean | bigint | number | string | ProgressiveBracket[];
export type EffectiveRuleSet = Record<string, ConstitutionalRuleValue>;

/**
 * Earth-default Corporation rules have their own public code so a
 * Corporation may override them, but their default value is supplied by the
 * Earth rule with the same policy meaning. Keep this mapping explicit so
 * inheritance cannot silently depend on duplicated seed rows.
 */
export function earthDefaultRuleCode(code: string): string | undefined {
  if (code === 'CORPORATION.HOUSE_CAPACITY.BASE_RATE') return 'EARTH.CAPACITY.BASE_RATE';
  if (code.startsWith('CORPORATION.GOVERNANCE.')) return code.replace('CORPORATION.GOVERNANCE.', 'EARTH.GOVERNANCE.');
  return undefined;
}

export function getConstitutionalRuleDefinition(code: string): ConstitutionalRuleDefinition {
  const found = CONSTITUTIONAL_RULE_DEFINITIONS.find((item) => item.code === code);
  if (!found) throw new Error(`Unknown constitutional rule: ${code}`);
  return found;
}

/** Convert player-facing decimal policy input into the canonical stored value. */
export function parseConstitutionalInputValue(code: string, value: unknown): unknown {
  const rule = getConstitutionalRuleDefinition(code);
  if (value == null) throw new Error(`Value is required for constitutional rule ${code}`);
  if (rule.valueType === 'CREDIT_UNITS') return parseCreditAmount(value);
  if (rule.valueType === 'RATE_BPS') return parsePercentageBps(value);
  if (rule.valueType === 'BOOLEAN') {
    if (typeof value !== 'boolean') throw new Error(`Boolean value is required for constitutional rule ${code}`);
    return value;
  }
  if (rule.valueType === 'ENUM') return String(value).trim();
  if (rule.valueType === 'INTEGER' || rule.valueType === 'GAME_DAYS' || rule.valueType === 'RESOURCE_UNITS') {
    const raw = String(value).trim();
    if (!/^\+?\d+$/.test(raw)) throw new Error(`Whole-number input is required for constitutional rule ${code}`);
    return BigInt(raw.replace(/^\+/, ''));
  }
  return String(value).trim();
}

function parsePercentageBps(value: unknown): bigint {
  const raw = String(value).trim().replace(/%$/, '');
  if (!/^\+?\d+(\.\d{1,2})?$/.test(raw)) throw new Error('Rate input must be a percentage such as 2.50');
  const unsigned = raw.replace(/^\+/, '');
  const [whole, fraction = ''] = unsigned.split('.');
  const bps = BigInt(whole) * 100n + BigInt(fraction.padEnd(2, '0'));
  if (bps > 10000n) throw new Error('Rate percentage cannot exceed 100.00%');
  return bps;
}

export function constitutionalInputSpec(definition: ConstitutionalRuleDefinition, validation?: unknown): ConstitutionalInputSpec {
  const base = (() => {
  switch (definition.valueType) {
    case 'CREDIT_UNITS':
      return { inputKind: 'DECIMAL_CREDIT', min: '0.00', max: null, step: '0.01', allowedValues: definition.allowedValues ?? [] };
    case 'RATE_BPS':
      return { inputKind: 'PERCENTAGE', min: '0.00', max: '100.00', step: '0.01', allowedValues: definition.allowedValues ?? [] };
    case 'ENUM':
      return { inputKind: 'ENUM', min: null, max: null, step: null, allowedValues: definition.allowedValues ?? [] };
    case 'BOOLEAN':
      return { inputKind: 'BOOLEAN', min: null, max: null, step: null, allowedValues: [] };
    case 'RESOURCE_UNITS':
      return { inputKind: 'RESOURCE_QUANTITY', min: '0', max: null, step: '1', allowedValues: [] };
    case 'PROGRESSIVE_SCHEDULE_REF':
      return { inputKind: 'SCHEDULE_ID', min: null, max: null, step: null, allowedValues: [] };
    default:
      return { inputKind: 'INTEGER', min: '0', max: null, step: '1', allowedValues: [] };
  }
  })();
  const schema = validation && typeof validation === 'object' && !Array.isArray(validation)
    ? validation as Record<string, unknown>
    : {};
  return {
    ...base,
    min: schema.min == null ? base.min : String(schema.min),
    max: schema.max == null ? base.max : String(schema.max),
    step: schema.step == null ? base.step : String(schema.step),
    allowedValues: Array.isArray(schema.allowedValues)
      ? schema.allowedValues.map(String)
      : base.allowedValues,
  };
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
    else if (rule.authorityModel === 'EARTH_DEFAULT_CORPORATION_OVERRIDE') {
      const inheritedValue = earthValue ?? (earthDefaultRuleCode(rule.code) ? input.earth[earthDefaultRuleCode(rule.code)!] : undefined);
      if (corporationValue !== undefined || inheritedValue !== undefined) resolved[rule.code] = corporationValue ?? inheritedValue;
    }
    else if (corporationValue !== undefined) resolved[rule.code] = corporationValue;
  }
  return resolved;
}
