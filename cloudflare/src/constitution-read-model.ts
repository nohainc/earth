export type ConstitutionAuthority = 'EARTH' | 'CORPORATION';

export type ConstitutionInputSpec = {
  inputKind: string;
  min: string | null;
  max: string | null;
  step: string | null;
  allowedValues: string[];
};

export type ResolvedConstitutionValue = {
  value: unknown;
  source: ConstitutionAuthority | null;
  versionId: string | null;
  effectiveFromGameDay: number | null;
};

export type ConstitutionRuleView = {
  code: string;
  articleCode: string;
  valueType: string;
  authorityModel: string;
  policyGroup: string;
  amendmentClass: string;
  calculationKey: string;
  allowedValues: unknown;
  validation: unknown;
  displayName: string;
  description: string;
  articleLabel: string;
  order: number;
  inputHint: string;
  displayHint: string;
  inputSpec: ConstitutionInputSpec;
  resolved: ResolvedConstitutionValue;
  /** The Earth value inherited by a Corporation override, when applicable. */
  earthDefault: ResolvedConstitutionValue | null;
  inheritanceStatus: 'EARTH' | 'INHERITED' | 'LOCAL_OVERRIDE' | null;
};

export type ConstitutionArticle = {
  articleCode: string;
  displayName: string;
  ruleCodes: string[];
};

export type ConstitutionProgressiveBracket = {
  ordinal: number;
  lowerBoundUnits: string;
  upperBoundUnits: string | null;
  marginalMultiplierNumerator: string;
  marginalMultiplierDenominator: string;
};

export type ConstitutionProgressiveSchedule = {
  id: string;
  code: string;
  basisType: string;
  authorityInstitutionId: string;
  version: number;
  effectiveFromGameDay: number;
  brackets: ConstitutionProgressiveBracket[];
};

export type ConstitutionChangeSet = {
  proposalId: string;
  authorityType: ConstitutionAuthority;
  authorityId: string;
  policyGroup: string;
  changes: unknown[];
  baseVersionSnapshot: Record<string, unknown>;
  effectiveFromGameDay: number | null;
};

export type ScheduledConstitutionChange = {
  ruleCode: string;
  authorityType: ConstitutionAuthority;
  authorityId: string;
  versionId: string;
  version: number;
  effectiveFromGameDay: number;
  proposalId: string | null;
  value: unknown;
};

export type ConstitutionVersionHistory = {
  ruleCode: string;
  authorityType: ConstitutionAuthority;
  authorityId: string;
  versionId: string;
  version: number;
  effectiveFromGameDay: number;
  effectiveToGameDay: number | null;
  status: string;
  proposalId: string | null;
  value: unknown;
};

export function constitutionArticleLabel(articleCode: string): string {
  switch (articleCode) {
    case 'TERRITORY_CAPACITY':
      return 'CAPACITY & SCARCITY';
    case 'EARTH_GOVERNANCE':
      return 'EARTH GOVERNANCE';
    case 'CORPORATION_GOVERNANCE':
      return 'CORPORATION GOVERNANCE';
    case 'TAXATION':
      return 'TAXATION & FISCAL';
    case 'SUCCESSION':
      return 'SUCCESSION';
    default:
      return articleCode.replaceAll('_', ' ');
  }
}

export function constitutionRuleLabel(code: string): string {
  const value = code.split('.').pop() ?? code;
  return value
    .split('_')
    .filter(Boolean)
    .map((part) => `${part.charAt(0)}${part.slice(1).toLowerCase()}`)
    .join(' ');
}
